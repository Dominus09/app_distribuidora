import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/session/operational_scope.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/sync/cache_integrity.dart';
import '../../../core/sync/visita_reconciliation.dart';
import '../../../core/utils/field_log.dart';
import '../models/visita.dart';

/// IDs locales y caché en disco de la ruta **por alcance operacional**
/// (`vendedor_id` + `fecha_operativa` + `ruta_id`).
class VendedorService {
  VendedorService();

  final _uuid = const Uuid();

  @Deprecated('Use OperationalScope.cacheKey')
  static String prefsKeyForVendedor(String vendedorId) =>
      OperationalScope.legacyVendorCacheKey(vendedorId);

  /// Filtra visitas que pertenecen al alcance operacional indicado.
  static List<Visita> filterForScope(
    List<Visita> visitas,
    OperationalScope scope,
  ) {
    final ref =
        OperationalScope.parseFechaOperativa(scope.fechaOperativa) ??
            DateTime.now();
    return visitas
        .where((v) => scope.matchesVisita(v, fechaCalendario: ref))
        .toList();
  }

  /// Fusiona GET de servidor con filas ya modificadas en el dispositivo (mismo alcance).
  static List<Visita> mergeServidorConLocales({
    required List<Visita> servidor,
    required List<Visita> locales,
  }) {
    if (locales.isEmpty) return List<Visita>.from(servidor);
    final localPorId = {for (final v in locales) v.id: v};
    final idsServidor = servidor.map((e) => e.id).toSet();
    final merged = servidor.map((s) {
      final l = localPorId[s.id];
      if (l == null) return s;
      return VisitaReconciliation.reconciliar(servidor: s, local: l);
    }).toList();

    final extras = <Visita>[];
    for (final l in locales) {
      if (idsServidor.contains(l.id)) continue;
      if (VisitaReconciliation.localTieneProgresoOperativo(l)) extras.add(l);
    }
    if (extras.isEmpty) return merged;
    return [...merged, ...extras];
  }

  static List<Visita> fusionarDiscoYMemoria({
    required List<Visita> disco,
    required List<Visita> memoria,
  }) {
    if (disco.isEmpty) return List<Visita>.from(memoria);
    if (memoria.isEmpty) return List<Visita>.from(disco);
    final memPorId = {for (final v in memoria) v.id: v};
    final discoIds = disco.map((e) => e.id).toSet();
    final out = <Visita>[];
    for (final d in disco) {
      final m = memPorId[d.id];
      if (m != null) {
        out.add(VisitaReconciliation.reconciliar(servidor: d, local: m));
      } else {
        out.add(d);
      }
    }
    for (final m in memoria) {
      if (!discoIds.contains(m.id) &&
          VisitaReconciliation.localTieneProgresoOperativo(m)) {
        out.add(m);
      }
    }
    out.sort((a, b) => a.orden.compareTo(b.orden));
    return out;
  }

  /// UUID v4 — idempotencia global por acción.
  String generateLocalActionId() => _uuid.v4();

  /// Persiste la ruta del alcance operacional en disco.
  Future<void> persistVisitasToDisk(
    OperationalScope scope,
    List<Visita> visitas,
  ) async {
    final scoped = filterForScope(visitas, scope);
    final prefs = await SharedPreferences.getInstance();
    final maps = scoped.map((v) => v.toJson()).toList(growable: false);
    final payload = CacheIntegrity.wrapWithIntegrity({
      'vendedor_codigo': scope.vendedorIdTrimmed,
      'fecha_operativa': scope.fechaOperativa,
      if (scope.rutaId != null) 'ruta_id': scope.rutaId,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'visitas': maps,
    });
    final encoded = scoped.length >= 25
        ? await compute(_encodeVisitaCachePayload, payload)
        : jsonEncode(payload);
    await prefs.setString(scope.cacheKey, encoded);
    fieldLog(
      'VendedorCache',
      'persist scope=$scope n=${scoped.length} key=${scope.cacheKey}',
    );
  }

  /// Carga la ruta guardada del alcance operacional indicado.
  Future<List<Visita>?> loadVisitasFromDisk(OperationalScope scope) async {
    final prefs = await SharedPreferences.getInstance();
    final rawScoped = prefs.getString(scope.cacheKey);
    final scoped = rawScoped != null && rawScoped.length > 48000
        ? await compute(
            _decodeVisitasIsolate,
            {
              'raw': rawScoped,
              'expectedOwner': scope.vendedorIdTrimmed,
              'fecha_operativa': scope.fechaOperativa,
              'ruta_id': scope.rutaId,
            },
          )
        : await _decodeVisitas(
            rawScoped,
            expectedOwner: scope.vendedorIdTrimmed,
            expectedFecha: scope.fechaOperativa,
            expectedRutaId: scope.rutaId,
          );
    if (scoped != null) return scoped;

    // Migración desde caché legacy por vendedor (sin fecha/ruta).
    final legacyVendor = await _decodeVisitas(
      prefs.getString(OperationalScope.legacyVendorCacheKey(scope.vendedorId)),
      expectedOwner: scope.vendedorIdTrimmed,
    );
    if (legacyVendor != null && legacyVendor.isNotEmpty) {
      final filtered = filterForScope(legacyVendor, scope);
      if (filtered.isNotEmpty) {
        fieldLog(
          'VendedorCache',
          'migrando legacy vendor → scope=$scope n=${filtered.length}',
        );
        await persistVisitasToDisk(scope, filtered);
        return filtered;
      }
    }

    // Migración desde caché global legacy.
    final legacyOwner = prefs.getString(SessionManager.legacyCacheOwnerKey);
    if (legacyOwner == scope.vendedorIdTrimmed) {
      final legacy = await _decodeVisitas(
        prefs.getString(OperationalScope.legacyGlobalCacheKey),
        expectedOwner: null,
      );
      if (legacy != null && legacy.isNotEmpty) {
        final filtered = filterForScope(legacy, scope);
        if (filtered.isNotEmpty) {
          fieldLog(
            'VendedorCache',
            'migrando legacy global → scope=$scope n=${filtered.length}',
          );
          await persistVisitasToDisk(scope, filtered);
          await prefs.remove(OperationalScope.legacyGlobalCacheKey);
          return filtered;
        }
      }
    }

    return null;
  }

  Future<List<Visita>?> _decodeVisitas(
    String? raw, {
    required String? expectedOwner,
    String? expectedFecha,
    int? expectedRutaId,
  }) async {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final schema = decoded['schema_version'];
        if (schema is int && schema > kVisitaCacheSchemaVersion) {
          fieldLog(
            'VendedorCache',
            'schema futuro $schema > $kVisitaCacheSchemaVersion',
          );
          return null;
        }
        if (!CacheIntegrity.verifyPayload(decoded)) {
          fieldLog('VendedorCache', 'checksum inválido — descartado');
          return null;
        }
        final owner = decoded['vendedor_codigo']?.toString().trim();
        if (expectedOwner != null &&
            owner != null &&
            owner.isNotEmpty &&
            owner != expectedOwner) {
          fieldLog(
            'VendedorCache',
            'descartado: owner=$owner esperado=$expectedOwner',
          );
          return null;
        }
        if (expectedFecha != null) {
          final f = decoded['fecha_operativa']?.toString().trim();
          if (f != null && f.isNotEmpty && f != expectedFecha) {
            return null;
          }
        }
        if (expectedRutaId != null && expectedRutaId >= 1) {
          final r = decoded['ruta_id'];
          if (r != null) {
            final ri = r is int ? r : int.tryParse(r.toString());
            if (ri != null && ri >= 1 && ri != expectedRutaId) {
              return null;
            }
          }
        }
        final list = decoded['visitas'];
        if (list is List<dynamic>) {
          return _parseVisitaList(list);
        }
      }
      if (decoded is List<dynamic>) {
        return _parseVisitaList(decoded);
      }
    } catch (e) {
      fieldLog('VendedorCache', 'JSON inválido: $e');
    }
    return null;
  }

  List<Visita> _parseVisitaList(List<dynamic> list) {
    return list
        .map((e) => Visita.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

String _encodeVisitaCachePayload(Map<String, dynamic> payload) {
  return jsonEncode(payload);
}

List<Visita>? _decodeVisitasIsolate(Map<String, dynamic> args) {
  final raw = args['raw'] as String?;
  final owner = args['expectedOwner'] as String?;
  final expectedFecha = args['fecha_operativa'] as String?;
  final expectedRutaId = args['ruta_id'] as int?;
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      final o = decoded['vendedor_codigo']?.toString().trim();
      if (owner != null && o != null && o.isNotEmpty && o != owner) {
        return null;
      }
      if (expectedFecha != null) {
        final f = decoded['fecha_operativa']?.toString().trim();
        if (f != null && f.isNotEmpty && f != expectedFecha) {
          return null;
        }
      }
      if (expectedRutaId != null && expectedRutaId >= 1) {
        final r = decoded['ruta_id'];
        if (r != null) {
          final ri = r is int ? r : int.tryParse(r.toString());
          if (ri != null && ri >= 1 && ri != expectedRutaId) {
            return null;
          }
        }
      }
      final list = decoded['visitas'];
      if (list is List<dynamic>) {
        return list
            .map((e) => Visita.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    }
    if (decoded is List<dynamic>) {
      return decoded
          .map((e) => Visita.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
  } catch (_) {}
  return null;
}

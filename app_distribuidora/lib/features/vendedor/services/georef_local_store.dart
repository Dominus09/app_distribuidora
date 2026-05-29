import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/session/operational_scope.dart';
import '../models/georef_pendiente.dart';
import '../models/georef_estado.dart';

/// Caché local de pendientes georef por alcance operacional.
class GeorefLocalStore {
  static String cacheKeyFor(OperationalScope scope) =>
      'georef_pendientes__${scope.vendedorIdTrimmed}__${scope.fechaOperativa}'
      '${scope.rutaId != null && scope.rutaId! >= 1 ? '__r${scope.rutaId}' : ''}';

  Future<List<GeorefPendiente>> load(OperationalScope scope) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(cacheKeyFor(scope));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map(
            (e) => GeorefPendiente.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(OperationalScope scope, List<GeorefPendiente> items) async {
    final prefs = await SharedPreferences.getInstance();
    final body = jsonEncode(items.map((e) => e.toJson()).toList());
    await prefs.setString(cacheKeyFor(scope), body);
  }

  Future<void> applyServerAck({
    required OperationalScope scope,
    required String clienteId,
    required int rutaId,
    required double lat,
    required double lon,
  }) async {
    final lista = await load(scope);
    final idx = lista.indexWhere(
      (e) => e.clienteId == clienteId && e.rutaId == rutaId,
    );
    if (idx < 0) return;
    lista[idx] = lista[idx].copyWith(
      latEfectiva: lat,
      lonEfectiva: lon,
      latOperacional: lat,
      lonOperacional: lon,
      georefEstado: GeorefEstado.aplicada,
      localSyncStatus: GeorefSyncStatus.synced,
    );
    await save(scope, lista);
  }

  /// KPI Home: `georef_pending_count__<vendedor>__<fecha_operativa>`.
  static String pendingCountKeyFor(OperationalScope scope) =>
      'georef_pending_count__${scope.vendedorIdTrimmed}__${scope.fechaOperativa}';

  static Future<int?> loadPendingCountCache(OperationalScope scope) async {
    final prefs = await SharedPreferences.getInstance();
    final key = pendingCountKeyFor(scope);
    if (!prefs.containsKey(key)) return null;
    return prefs.getInt(key);
  }

  static Future<void> savePendingCountCache(
    OperationalScope scope,
    int count,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(pendingCountKeyFor(scope), count);
  }

  /// Elimina claves KPI antiguas sin fecha (evita 155 de otro contexto).
  static Future<void> purgeLegacyPendingCountCaches() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getKeys().where((k) {
      if (!k.startsWith('georef_pending_count__')) return false;
      return k.split('__').length == 2;
    });
    for (final k in legacy) {
      await prefs.remove(k);
    }
  }

  /// Fusiona servidor con cambios locales pendientes (no pierde capturas offline).
  static List<GeorefPendiente> mergeServidorConLocal({
    required List<GeorefPendiente> servidor,
    required List<GeorefPendiente> local,
  }) {
    if (local.isEmpty) return List<GeorefPendiente>.from(servidor);
    final localPorClave = {for (final l in local) l.claveLocal: l};
    final merged = servidor.map((s) {
      final l = localPorClave[s.claveLocal];
      if (l == null) return s;
      if (l.localSyncStatus.necesitaPush ||
          l.georefEstado.index > s.georefEstado.index) {
        return l.copyWith(
          clienteNombre: s.clienteNombre,
          direccion: s.direccion,
          comuna: s.comuna,
          ciudad: s.ciudad ?? l.ciudad,
          ruteroId: s.ruteroId ?? l.ruteroId,
          georefOrigen: l.georefOrigen ?? s.georefOrigen,
        );
      }
      return s;
    }).toList();
    final ids = merged.map((e) => e.claveLocal).toSet();
    for (final l in local) {
      if (!ids.contains(l.claveLocal) && l.localSyncStatus.necesitaPush) {
        merged.add(l);
      }
    }
    return merged;
  }
}

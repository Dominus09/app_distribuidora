import 'dart:convert';
import 'dart:math' show Random;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/visita.dart';

/// IDs locales y caché en disco de la ruta (sin mock de clientes).
class VendedorService {
  VendedorService();

  static const _prefsKeyRuta = 'vendedor_ruta_visitas_json';

  final _random = Random();
  int _actionSeq = 0;

  /// Fusiona GET de servidor con filas ya modificadas en el dispositivo.
  ///
  /// Evita que una recarga de ruta borre visitas, incidencias o cola de sync local.
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
      if (!_localTieneProgresoOperativo(l)) return s;
      return _mergeMaestroServidorEnLocal(l, s);
    }).toList();

    final extras = <Visita>[];
    for (final l in locales) {
      if (idsServidor.contains(l.id)) continue;
      if (_localTieneProgresoOperativo(l)) extras.add(l);
    }
    if (extras.isEmpty) return merged;
    return [...merged, ...extras];
  }

  /// Al reanudar la app: prioriza datos persistidos y superpone memoria si es más reciente.
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
      if (m != null &&
          _localTieneProgresoOperativo(m) &&
          (!_localTieneProgresoOperativo(d) ||
              _prioridadLocal(m) >= _prioridadLocal(d))) {
        out.add(_mergeMaestroServidorEnLocal(m, d));
      } else {
        out.add(d);
      }
    }
    for (final m in memoria) {
      if (!discoIds.contains(m.id) && _localTieneProgresoOperativo(m)) {
        out.add(m);
      }
    }
    out.sort((a, b) => a.orden.compareTo(b.orden));
    return out;
  }

  static int _prioridadLocal(Visita v) {
    var p = 0;
    if (v.estado != VisitaEstado.pendiente) p += 1000;
    switch (v.syncStatus) {
      case SyncStatus.pendingSync:
      case SyncStatus.syncing:
      case SyncStatus.syncError:
        p += 100;
      case SyncStatus.synced:
        p += 0;
    }
    if ((v.localActionId ?? '').isNotEmpty) p += 10;
    if (v.fechaHoraVisita != null) p += 1;
    return p;
  }

  static bool _localTieneProgresoOperativo(Visita l) {
    if (l.estado != VisitaEstado.pendiente) return true;
    if (l.syncStatus != SyncStatus.synced) return true;
    if ((l.localActionId ?? '').isNotEmpty) return true;
    if (l.latVisita != null && l.lonVisita != null) return true;
    if (l.fechaHoraVisita != null) return true;
    return false;
  }

  static Visita _mergeMaestroServidorEnLocal(Visita local, Visita servidor) {
    return local.copyWith(
      clienteNombre: servidor.clienteNombre,
      nombreFantasia: servidor.nombreFantasia,
      direccion: servidor.direccion,
      comuna: servidor.comuna,
      rutClean: servidor.rutClean,
      diaOperativo: servidor.diaOperativo,
      orden: servidor.orden,
      rutaId: servidor.rutaId ?? local.rutaId,
      latCliente: servidor.latCliente,
      lonCliente: servidor.lonCliente,
      clienteId: servidor.clienteId ?? local.clienteId,
    );
  }

  /// ID único por acción guardada (visitado / incidencia) para idempotencia al sincronizar.
  String generateLocalActionId() {
    _actionSeq++;
    return 'act_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}_$_actionSeq';
  }

  /// Persiste la ruta actual en el dispositivo (offline / respaldo).
  Future<void> persistVisitasToDisk(List<Visita> visitas) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded =
        jsonEncode(visitas.map((v) => v.toJson()).toList(growable: false));
    await prefs.setString(_prefsKeyRuta, encoded);
  }

  /// Carga la última ruta guardada en disco (si existe).
  Future<List<Visita>?> loadVisitasFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyRuta);
    if (raw == null || raw.isEmpty) return null;
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Visita.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

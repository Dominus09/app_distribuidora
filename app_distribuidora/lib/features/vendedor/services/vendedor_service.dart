import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/visita.dart';

/// IDs locales y caché en disco de la ruta (sin mock de clientes).
class VendedorService {
  VendedorService();

  static const _prefsKeyRuta = 'vendedor_ruta_visitas_json';

  final _random = Random();
  int _actionSeq = 0;

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

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../models/visita.dart';
import 'visitas_api_payload.dart';

/// Respuesta de POST `/app_distribuidora/visitas/sync` (`SyncResponse` en OpenAPI).
class SyncApiResult {
  const SyncApiResult({
    required this.sincronizados,
    required this.omitidos,
    required this.errores,
  });

  final int sincronizados;
  final int omitidos;
  final int errores;
}

/// Cliente HTTP para el backend FastAPI del módulo vendedor.
class ApiService {
  ApiService({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  final http.Client _client;

  /// Comprueba que el servidor API responde (internet real, no solo interfaz activa).
  /// Usa OpenAPI de FastAPI; tolera 3xx–4xx como “alcanzable” (red y DNS OK).
  Future<bool> pingReachable({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = _uri('openapi.json');
    try {
      final resp = await _client
          .get(
            uri,
            headers: {'Accept': 'application/json'},
          )
          .timeout(timeout);
      return resp.statusCode < 500;
    } on Object {
      return false;
    }
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    var u = Uri.parse('$base$p');
    if (query != null && query.isNotEmpty) {
      u = u.replace(queryParameters: query);
    }
    return u;
  }

  /// GET `/vendedor/ruta` → cuerpo `RutaResponse` con lista `visitas`.
  Future<List<Visita>> getRutaDelDia(String fecha, String vendedor) async {
    final uri = _uri(
      'vendedor/ruta',
      {'fecha': fecha, 'vendedor': vendedor},
    );
    final resp = await _client.get(
      uri,
      headers: {'Accept': 'application/json'},
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiHttpException(resp.statusCode, resp.body);
    }
    final decoded = jsonDecode(resp.body);
    return _parseRutaOListaVisitas(decoded);
  }

  List<Visita> _parseRutaOListaVisitas(dynamic decoded) {
    if (decoded is List<dynamic>) {
      return decoded
          .map((e) => Visita.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    if (decoded is Map<String, dynamic>) {
      final rutaIdPadre = decoded['id'];
      final rawVisitas = decoded['visitas'];
      if (rawVisitas is List<dynamic>) {
        return rawVisitas.map((e) {
          final row = Map<String, dynamic>.from(e as Map);
          if (!row.containsKey('ruta_id') && rutaIdPadre != null) {
            row['ruta_id'] = rutaIdPadre;
          }
          return Visita.fromJson(row);
        }).toList();
      }
      for (final key in ['data', 'items', 'results']) {
        final v = decoded[key];
        if (v is List<dynamic>) {
          return v
              .map((e) => Visita.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
      }
    }
    if (decoded is Map) {
      return _parseRutaOListaVisitas(Map<String, dynamic>.from(decoded));
    }
    throw const FormatException(
      'Respuesta GET ruta: se esperaba RutaResponse o lista de visitas',
    );
  }

  /// POST `/visitas` — actualización de visita existente (`id` obligatorio en cuerpo).
  Future<Visita> registrarVisita(Visita visita) async {
    final uri = _uri('visitas');
    final raw = visita.toJsonForApiCreate();
    final requestBody = await appendFotoBase64IfPlatformSupported(raw, visita);
    final resp = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(requestBody),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiHttpException(resp.statusCode, resp.body);
    }
    if (resp.body.isEmpty) {
      return visita;
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      return visita;
    }
    final m = Map<String, dynamic>.from(decoded);
    final data = m['data'];
    if (data is Map) {
      return Visita.fromJson(Map<String, dynamic>.from(data));
    }
    if (m.containsKey('id') && m.containsKey('ruta_id')) {
      return Visita.fromJson(m);
    }
    return visita;
  }

  /// POST `/visitas/sync` — cuerpo `SyncRequest`; respuesta `SyncResponse` (solo contadores).
  Future<SyncApiResult> syncVisitas(List<Visita> visitas) async {
    final uri = _uri('visitas/sync');
    final list = <Map<String, dynamic>>[];
    for (final v in visitas) {
      final raw = v.toJsonForApiCreate();
      list.add(await appendFotoBase64IfPlatformSupported(raw, v));
    }
    final payload = {'visitas': list};
    final resp = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(payload),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiHttpException(resp.statusCode, resp.body);
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw const FormatException('SyncResponse: se esperaba un objeto JSON');
    }
    final m = Map<String, dynamic>.from(decoded);
    return SyncApiResult(
      sincronizados: _parseIntCuenta(m['sincronizados']),
      omitidos: _parseIntCuenta(m['omitidos']),
      errores: _parseIntCuenta(m['errores']),
    );
  }

  static int _parseIntCuenta(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

class ApiHttpException implements Exception {
  ApiHttpException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiHttpException($statusCode): $body';
}

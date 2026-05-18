import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../models/visita.dart';
import 'visitas_api_payload.dart';

const Duration _kGetRutaTimeout = Duration(seconds: 45);
const Duration _kPostVisitaTimeout = Duration(seconds: 25);
const Duration _kPostSyncTimeout = Duration(seconds: 45);
const Duration _kPostTelemetryTimeout = Duration(seconds: 20);

/// Resultado de [ApiService.checkReachability] (OpenAPI `GET …/openapi.json`).
enum ApiReachabilityKind {
  ok,
  timeout,
  networkUnreachable,
  clientTransportError,
  serverError,
  responseShapeError,
  unknown,
}

/// Detalle de llegada al API (logs + mensaje de usuario).
class ApiReachabilityOutcome {
  const ApiReachabilityOutcome._({
    required this.kind,
    required this.detail,
    required this.userMessage,
  });

  final ApiReachabilityKind kind;
  final String detail;
  final String userMessage;

  bool get ok => kind == ApiReachabilityKind.ok;

  String get logLine => 'reachability kind=$kind detail=$detail';

  static const ApiReachabilityOutcome success = ApiReachabilityOutcome._(
    kind: ApiReachabilityKind.ok,
    detail: 'openapi.json respondió',
    userMessage: '',
  );

  factory ApiReachabilityOutcome.timeoutWait(Duration waited) {
    return ApiReachabilityOutcome._(
      kind: ApiReachabilityKind.timeout,
      detail: '${waited.inMilliseconds}ms',
      userMessage:
          'Tiempo de espera al contactar el servidor. Revisa la red hacia el API o vuelve a intentar.',
    );
  }

  factory ApiReachabilityOutcome.network(String message) {
    final m = message.trim();
    return ApiReachabilityOutcome._(
      kind: ApiReachabilityKind.networkUnreachable,
      detail: m,
      userMessage: m.isEmpty
          ? 'No se pudo establecer conexión de red con el servidor.'
          : 'Sin ruta de red hacia el servidor: $m',
    );
  }

  factory ApiReachabilityOutcome.clientHttp(String message) {
    final m = message.trim();
    return ApiReachabilityOutcome._(
      kind: ApiReachabilityKind.clientTransportError,
      detail: m,
      userMessage: m.isEmpty
          ? 'Fallo al conectar con el servidor (cliente HTTP).'
          : 'Error de red/HTTP al contactar el servidor: $m',
    );
  }

  factory ApiReachabilityOutcome.httpError(int status, String snippet) {
    return ApiReachabilityOutcome._(
      kind: ApiReachabilityKind.serverError,
      detail: 'HTTP $status $snippet',
      userMessage: 'El servidor respondió con error HTTP $status'
          '${snippet.isEmpty ? '.' : ': $snippet'}',
    );
  }

  factory ApiReachabilityOutcome.badOpenApiJson(String message) {
    return ApiReachabilityOutcome._(
      kind: ApiReachabilityKind.responseShapeError,
      detail: message,
      userMessage:
          'El servidor respondió, pero la respuesta no es JSON válido (OpenAPI). $message',
    );
  }

  factory ApiReachabilityOutcome.unknown(Object e) {
    final s = e.toString().trim();
    return ApiReachabilityOutcome._(
      kind: ApiReachabilityKind.unknown,
      detail: s,
      userMessage: s.isEmpty
          ? 'Error desconocido al comprobar el servidor.'
          : 'Error al comprobar el servidor: $s',
    );
  }
}

/// ACK de telemetría (`POST /operaciones/heartbeat` o `/operaciones/gps_track`).
class TelemetryAck {
  const TelemetryAck({required this.confirmed, this.serverTimestamp});

  final bool confirmed;
  final DateTime? serverTimestamp;
}

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

  static String _snippetBody(String body, {int max = 140}) {
    final oneLine = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (oneLine.length <= max) return oneLine;
    return '${oneLine.substring(0, max)}…';
  }

  /// Comprueba que el servidor API responde (red + DNS + handshake + HTTP).
  /// Tolera 3xx–4xx como “alcanzable” para descartar sólo caídas/red/5xx obvias.
  Future<ApiReachabilityOutcome> checkReachability({
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
      if (resp.statusCode >= 500) {
        return ApiReachabilityOutcome.httpError(
          resp.statusCode,
          _snippetBody(resp.body),
        );
      }
      if (resp.statusCode < 200) {
        return ApiReachabilityOutcome.httpError(
          resp.statusCode,
          _snippetBody(resp.body),
        );
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = resp.body.trim();
        if (body.isEmpty) {
          return ApiReachabilityOutcome.badOpenApiJson('Cuerpo vacío.');
        }
        try {
          final decoded = jsonDecode(body);
          if (decoded is! Map && decoded is! List) {
            return ApiReachabilityOutcome.badOpenApiJson(
              'Se esperaba JSON objeto o lista.',
            );
          }
        } on FormatException catch (e) {
          return ApiReachabilityOutcome.badOpenApiJson(e.message);
        }
        return ApiReachabilityOutcome.success;
      }

      /// 3xx / 4xx: el equipo remoto contesta (similar a ping tolerante anterior).
      return ApiReachabilityOutcome._(
        kind: ApiReachabilityKind.ok,
        detail:
            'HTTP ${resp.statusCode} (${_snippetBody(resp.body)})',
        userMessage: '',
      );
    } on TimeoutException {
      return ApiReachabilityOutcome.timeoutWait(timeout);
    } on SocketException catch (e) {
      return ApiReachabilityOutcome.network(e.message);
    } on http.ClientException catch (e) {
      return ApiReachabilityOutcome.clientHttp(e.message);
    } catch (e) {
      return ApiReachabilityOutcome.unknown(e);
    }
  }

  /// Comprueba que el servidor API responde (internet real, no solo interfaz activa).
  /// Usa OpenAPI de FastAPI; tolera 3xx–4xx como “alcanzable” (red y DNS OK).
  Future<bool> pingReachable({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final o = await checkReachability(timeout: timeout);
    return o.ok;
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
    final resp = await _client
        .get(
          uri,
          headers: {'Accept': 'application/json'},
        )
        .timeout(_kGetRutaTimeout);
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
    final resp = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(requestBody),
        )
        .timeout(_kPostVisitaTimeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiHttpException(resp.statusCode, resp.body);
    }
    if (resp.body.isEmpty) {
      return visita;
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(resp.body);
    } on FormatException catch (e) {
      throw ApiHttpException(
        resp.statusCode,
        'JSON inválido en respuesta de visitas: ${e.message}',
      );
    }
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
    final resp = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(_kPostSyncTimeout);
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

  /// POST `/operaciones/heartbeat` — sesión operacional viva + GPS.
  Future<TelemetryAck> postHeartbeat(Map<String, dynamic> payload) async {
    return _postTelemetryAck('operaciones/heartbeat', payload);
  }

  /// POST `/operaciones/gps_track` — puntos GPS para km recorridos.
  Future<TelemetryAck> postGpsTrack(Map<String, dynamic> payload) async {
    return _postTelemetryAck('operaciones/gps_track', payload);
  }

  Future<TelemetryAck> _postTelemetryAck(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri(path);
    final resp = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(_kPostTelemetryTimeout);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiHttpException(resp.statusCode, resp.body);
    }

    if (resp.body.isEmpty) {
      return const TelemetryAck(confirmed: true);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(resp.body);
    } on FormatException {
      return const TelemetryAck(confirmed: true);
    }

    if (decoded is! Map) {
      return const TelemetryAck(confirmed: true);
    }

    final m = Map<String, dynamic>.from(decoded);
    final ack = m['ack'] ?? m['confirmed'] ?? m['synced'] ?? m['ok'];
    final confirmed = ack == true ||
        ack == 1 ||
        (ack is String && ack.toLowerCase() == 'true');

    DateTime? serverTs;
    final tsRaw = m['server_timestamp'] ?? m['timestamp'] ?? m['sync_confirmed_at'];
    if (tsRaw is String) {
      serverTs = DateTime.tryParse(tsRaw);
    }

    return TelemetryAck(
      confirmed: confirmed || resp.statusCode == 200,
      serverTimestamp: serverTs,
    );
  }
}

class ApiHttpException implements Exception {
  ApiHttpException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiHttpException($statusCode): $body';
}

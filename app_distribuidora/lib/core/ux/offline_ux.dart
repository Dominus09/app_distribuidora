import 'dart:async';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../../features/vendedor/services/api_service.dart';

/// Mensajes y reglas UX para operación sin red.
abstract final class OfflineUx {
  static const guardadoSinConexion =
      'Guardado sin conexión. Se enviará automáticamente.';
  static const guardadoPendienteEnvio =
      'Registro guardado. Pendiente de envío al servidor.';
  static const enviadoAlServidor =
      'Registro enviado y sincronizado con el servidor.';

  /// Si la interfaz no tiene datos, no intentar HTTP (evita DNS/timeout).
  static bool debeOmitirHttp({
    required bool interfaceConnectivityDetected,
    required bool attemptRemoteSave,
    required bool forceOffline,
  }) {
    if (forceOffline || !attemptRemoteSave) return true;
    return !interfaceConnectivityDetected;
  }

  static String mensajeTrasGuardarLocal({
    required bool omitirHttp,
  }) {
    if (omitirHttp) return guardadoSinConexion;
    return guardadoPendienteEnvio;
  }

  /// Errores de red/timeout: no alarmar al vendedor (ya quedó en disco).
  static bool esFalloRedTransitorio(Object? error) {
    if (error == null) return false;
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;
    if (error is http.ClientException) return true;
    return false;
  }

  static bool debeMostrarErrorAlUsuario(Object? error) {
    if (error == null) return false;
    if (esFalloRedTransitorio(error)) return false;
    if (error is String) {
      if (error == guardadoSinConexion) return false;
      final s = sanitizarMensajeError(error);
      if (s == guardadoSinConexion) return false;
    }
    return true;
  }

  static String mensajeReachabilityUsuario(ApiReachabilityOutcome reach) {
    if (reach.ok) return '';
    return switch (reach.kind) {
      ApiReachabilityKind.timeout => guardadoSinConexion,
      ApiReachabilityKind.networkUnreachable => guardadoSinConexion,
      ApiReachabilityKind.clientTransportError => guardadoSinConexion,
      _ => guardadoPendienteEnvio,
    };
  }

  /// Oculta "failed host lookup" y similares en SnackBars.
  static String sanitizarMensajeError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('host lookup') ||
        lower.contains('failed host') ||
        lower.contains('socketexception') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection refused') ||
        lower.contains('connection timed out') ||
        lower.contains('timed out')) {
      return guardadoSinConexion;
    }
    return raw;
  }
}

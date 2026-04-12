import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/api_config.dart';
import '../models/login_response.dart';

/// Claves de sesión (no chocan con `vendedor_ruta_visitas_json` del módulo ruta).
abstract final class AuthSessionKeys {
  static const loggedIn = 'distribuidora_auth_logged_in';
  static const vendedorCodigo = 'distribuidora_auth_vendedor_codigo';
  static const vendedorNombre = 'distribuidora_auth_vendedor_nombre';
}

/// Login real contra `POST .../login` y persistencia con [SharedPreferences].
///
/// No modifica [ApiService] del módulo vendedor; usa HTTP aquí.
class DistribuidoraAuthService {
  DistribuidoraAuthService({http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  final http.Client _client;

  Uri _loginUri() {
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    return Uri.parse('$base/login');
  }

  /// POST `/app_distribuidora/login` con `codigo` y `password`.
  ///
  /// Si la respuesta indica éxito, guarda sesión en [SharedPreferences].
  Future<LoginResponse> login(String codigo, String password) async {
    final trimmedCodigo = codigo.trim();
    final trimmedPass = password;

    try {
      final resp = await _client
          .post(
            _loginUri(),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'codigo': trimmedCodigo,
              'password': trimmedPass,
            }),
          )
          .timeout(const Duration(seconds: 25));

      Map<String, dynamic>? map;
      if (resp.body.isNotEmpty) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        }
      }

      if (resp.statusCode == 401 ||
          resp.statusCode == 403 ||
          resp.statusCode == 422) {
        return const LoginResponse(success: false);
      }

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw HttpException('HTTP ${resp.statusCode}', uri: _loginUri());
      }

      if (map == null) {
        return const LoginResponse(success: false);
      }

      final parsed = LoginResponse.fromJson(map);
      if (!parsed.success) {
        return parsed;
      }

      final vendedor = parsed.vendedor ?? trimmedCodigo;
      final nombre = parsed.nombre ?? vendedor;
      await _persistSession(vendedor, nombre);
      return LoginResponse(
        success: true,
        vendedor: vendedor,
        nombre: nombre,
      );
    } on SocketException {
      rethrow;
    } on http.ClientException {
      rethrow;
    } on FormatException {
      rethrow;
    }
  }

  Future<void> _persistSession(String codigo, String nombre) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AuthSessionKeys.loggedIn, true);
    await prefs.setString(AuthSessionKeys.vendedorCodigo, codigo);
    await prefs.setString(AuthSessionKeys.vendedorNombre, nombre);
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AuthSessionKeys.loggedIn) ?? false;
  }

  Future<String?> readVendedorCodigo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AuthSessionKeys.vendedorCodigo);
  }

  Future<String?> readVendedorNombre() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AuthSessionKeys.vendedorNombre);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AuthSessionKeys.loggedIn, false);
    await prefs.remove(AuthSessionKeys.vendedorCodigo);
    await prefs.remove(AuthSessionKeys.vendedorNombre);
  }
}

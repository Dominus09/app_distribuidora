import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../utils/field_log.dart';
import 'operational_scope.dart';

/// Resultado de activar sesión tras login o arranque con sesión guardada.
class SessionActivation {
  const SessionActivation({
    required this.vendedorId,
    required this.sessionId,
    required this.vendorChanged,
  });

  final String vendedorId;
  final String sessionId;

  /// `true` si el vendedor activo cambió respecto al anterior en runtime/prefs.
  final bool vendorChanged;
}

/// Sesión operacional activa: vendedor actual + id de sesión (heartbeat/GPS).
class SessionManager {
  SessionManager._();
  static final SessionManager instance = SessionManager._();

  static const _prefsActiveVendedor = 'distribuidora_active_vendedor_id';
  static const _prefsSessionId = 'distribuidora_active_session_id';
  static const _prefsFechaOperativa = 'distribuidora_active_fecha_operativa';
  static const _prefsRutaId = 'distribuidora_active_ruta_id';
  static const legacyCacheOwnerKey = 'vendedor_legacy_cache_owner';

  final _uuid = const Uuid();

  String? _vendedorId;
  String? _sessionId;
  OperationalScope? _operationalScope;

  String? get currentVendedorId => _vendedorId;
  String? get sessionId => _sessionId;
  OperationalScope? get operationalScope => _operationalScope;

  String requireVendedorId() {
    final id = _vendedorId?.trim();
    if (id == null || id.isEmpty) {
      throw StateError('No hay vendedor activo en la sesión operacional.');
    }
    return id;
  }

  /// Restaura sesión desde prefs (arranque en frío) sin rotar session_id.
  Future<void> hydrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _vendedorId = prefs.getString(_prefsActiveVendedor)?.trim();
    _sessionId = prefs.getString(_prefsSessionId);
    _operationalScope = await _readOperationalScopeFromPrefs(prefs);
    fieldLog(
      'Session',
      'hydrate vendedor=${_vendedorId ?? "—"} session=${_sessionId ?? "—"} '
      'scope=${_operationalScope ?? "—"}',
    );
  }

  /// Activa sesión tras login. En arranque en frío con mismo vendedor conserva session_id.
  Future<SessionActivation> activateForLogin(
    String vendedorCodigo, {
    bool preserveSessionIfSameVendor = false,
  }) async {
    final id = vendedorCodigo.trim();
    if (id.isEmpty) {
      throw ArgumentError('vendedorCodigo vacío');
    }

    final prefs = await SharedPreferences.getInstance();
    final previous =
        _vendedorId ?? prefs.getString(_prefsActiveVendedor)?.trim();
    final changed = previous != null && previous.isNotEmpty && previous != id;

    if (preserveSessionIfSameVendor &&
        !changed &&
        (_sessionId?.isNotEmpty ?? false)) {
      _vendedorId = id;
      await prefs.setString(_prefsActiveVendedor, id);
      fieldLog(
        'Session',
        'reactivate vendedor=$id session=$_sessionId (preservada)',
      );
      return SessionActivation(
        vendedorId: id,
        sessionId: _sessionId!,
        vendorChanged: false,
      );
    }

    _vendedorId = id;
    _sessionId = _uuid.v4();
    _operationalScope = null;

    await prefs.setString(_prefsActiveVendedor, id);
    await prefs.setString(_prefsSessionId, _sessionId!);
    await prefs.remove(_prefsFechaOperativa);
    await prefs.remove(_prefsRutaId);

    await _claimLegacyCacheOwnerIfNeeded(prefs, id);

    fieldLog(
      'Session',
      'activate vendedor=$id changed=$changed session=$_sessionId',
    );

    return SessionActivation(
      vendedorId: id,
      sessionId: _sessionId!,
      vendorChanged: changed,
    );
  }

  /// Persiste el alcance operacional activo (fecha + ruta del día).
  Future<void> setOperationalScope(OperationalScope scope) async {
    _operationalScope = scope;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsFechaOperativa, scope.fechaOperativa);
    final rid = scope.rutaId;
    if (rid != null && rid >= 1) {
      await prefs.setInt(_prefsRutaId, rid);
    } else {
      await prefs.remove(_prefsRutaId);
    }
    fieldLog('Session', 'scope activo=$scope');
  }

  /// Lee alcance persistido para un vendedor (puede ser de sesión anterior).
  Future<OperationalScope?> loadOperationalScope(String vendedorId) async {
    final prefs = await SharedPreferences.getInstance();
    return _readOperationalScopeFromPrefs(prefs, vendedorId: vendedorId);
  }

  Future<OperationalScope?> _readOperationalScopeFromPrefs(
    SharedPreferences prefs, {
    String? vendedorId,
  }) async {
    final vid =
        (vendedorId ?? _vendedorId ?? prefs.getString(_prefsActiveVendedor))
            ?.trim();
    final fecha = prefs.getString(_prefsFechaOperativa)?.trim();
    if (vid == null || vid.isEmpty || fecha == null || fecha.isEmpty) {
      return null;
    }
    final rutaId = prefs.getInt(_prefsRutaId);
    return OperationalScope(
      vendedorId: vid,
      fechaOperativa: fecha,
      rutaId: rutaId != null && rutaId >= 1 ? rutaId : null,
    );
  }

  /// Primera sesión tras actualizar: asocia caché legacy global al vendedor que inicia sesión.
  Future<void> _claimLegacyCacheOwnerIfNeeded(
    SharedPreferences prefs,
    String vendedorId,
  ) async {
    if (prefs.containsKey(legacyCacheOwnerKey)) return;
    if (!prefs.containsKey(OperationalScope.legacyGlobalCacheKey)) return;
    await prefs.setString(legacyCacheOwnerKey, vendedorId);
    fieldLog('Session', 'legacy cache reclamado por vendedor=$vendedorId');
  }

  /// Cierra sesión runtime (no borra datos por vendedor/fecha en disco/SQLite).
  Future<void> clearOnLogout() async {
    _vendedorId = null;
    _sessionId = null;
    _operationalScope = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsActiveVendedor);
    await prefs.remove(_prefsSessionId);
    await prefs.remove(_prefsFechaOperativa);
    await prefs.remove(_prefsRutaId);
    fieldLog('Session', 'logout → sesión runtime limpia');
  }
}

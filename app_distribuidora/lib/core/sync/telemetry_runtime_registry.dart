/// Garantiza un solo coordinador de telemetría activo por vendedor.
class TelemetryRuntimeRegistry {
  TelemetryRuntimeRegistry._();
  static final TelemetryRuntimeRegistry instance = TelemetryRuntimeRegistry._();

  String? _activeVendedorId;
  Object? _activeOwner;

  bool tryAcquire(String vendedorId, Object owner) {
    final id = vendedorId.trim();
    if (_activeVendedorId == id && _activeOwner == owner) return true;
    if (_activeVendedorId != null && _activeVendedorId != id) {
      return false;
    }
    if (_activeOwner != null && _activeOwner != owner) {
      return false;
    }
    _activeVendedorId = id;
    _activeOwner = owner;
    return true;
  }

  void release(Object owner) {
    if (_activeOwner == owner) {
      _activeOwner = null;
      _activeVendedorId = null;
    }
  }

  bool get hasActiveCoordinator => _activeOwner != null;
}

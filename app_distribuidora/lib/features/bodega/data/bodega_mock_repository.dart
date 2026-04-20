import 'package:flutter/foundation.dart';

import '../models/camion_mock.dart';
import '../models/picking_producto_mock.dart';
import 'bodega_mock_seed.dart';

/// Estado mock global de bodega (sin HTTP).
class BodegaMockRepository extends ChangeNotifier {
  BodegaMockRepository._() : _camiones = buildBodegaMockCamiones();

  static final BodegaMockRepository instance = BodegaMockRepository._();

  List<CamionMock> _camiones;

  List<CamionMock> get camiones => List<CamionMock>.unmodifiable(_camiones);

  CamionMock camion(String id) {
    return _camiones.firstWhere((c) => c.id == id);
  }

  int indexCamion(String id) => _camiones.indexWhere((c) => c.id == id);

  void _reemplazarCamion(int i, CamionMock c) {
    _camiones = [..._camiones]..[i] = c;
    notifyListeners();
  }

  void setCargaRealCajas(String camionId, String productoId, int cajas) {
    final i = indexCamion(camionId);
    if (i < 0) return;
    final c = _camiones[i];
    final pj = c.productos.indexWhere((p) => p.id == productoId);
    if (pj < 0) return;
    final p = c.productos[pj];
    final clamped = cajas.clamp(0, 9999);
    final nextP = p.copyWith(cargaRealCajas: clamped);
    final nextList = [...c.productos]..[pj] = nextP;
    _reemplazarCamion(i, c.copyWith(productos: nextList));
  }

  /// `true` si el código coincide con el esperado.
  bool validarCodigoProducto(String camionId, String productoId, String codigoIngresado) {
    final i = indexCamion(camionId);
    if (i < 0) return false;
    final c = _camiones[i];
    final pj = c.productos.indexWhere((p) => p.id == productoId);
    if (pj < 0) return false;
    final p = c.productos[pj];
    final ok = p.codigoBarras.trim() == codigoIngresado.trim();
    final nextP = ok
        ? p.copyWith(codigoValidado: true, hayErrorCodigo: false)
        : p.copyWith(hayErrorCodigo: true, codigoValidado: false);
    final nextList = [...c.productos]..[pj] = nextP;
    _reemplazarCamion(i, c.copyWith(productos: nextList));
    return ok;
  }

  /// Líneas con carga incompleta vs objetivo.
  List<PickingProductoMock> productosConFaltante(String camionId) {
    final c = camion(camionId);
    return c.productos.where((p) => p.cargaRealCajas < p.cajasObjetivo).toList();
  }

  int contarLineasCompletas(String camionId) {
    final c = camion(camionId);
    return c.productos.where((p) => p.pickingLineaCompleta).length;
  }
}

import 'picking_producto_mock.dart';

/// Camión del día con picking asociado (mock).
class CamionMock {
  const CamionMock({
    required this.id,
    required this.nombre,
    required this.clientesCount,
    required this.montoTotalPesos,
    required this.productos,
  });

  final String id;
  final String nombre;
  final int clientesCount;
  final int montoTotalPesos;
  final List<PickingProductoMock> productos;

  int get lineasCount => productos.length;

  int get unidadesTotales =>
      productos.fold(0, (a, p) => a + p.unidadesObjetivo);

  int get cajasTotalesObjetivo =>
      productos.fold(0, (a, p) => a + p.cajasObjetivo);

  CamionMock copyWith({List<PickingProductoMock>? productos}) {
    return CamionMock(
      id: id,
      nombre: nombre,
      clientesCount: clientesCount,
      montoTotalPesos: montoTotalPesos,
      productos: productos ?? this.productos,
    );
  }
}

import '../models/camion_mock.dart';
import '../models/picking_producto_mock.dart';

const _hinoId = 'camion_hino_3';
const _hyundaiId = 'camion_hyundai';

PickingProductoMock _p(
  String id,
  String tipo,
  String nombre,
  String variante,
  int cxc,
  String codigo,
  int unidades,
  int cajas,
  String camionId,
) {
  return PickingProductoMock(
    id: id,
    camionId: camionId,
    tipoProducto: tipo,
    nombreProducto: nombre,
    variante: variante,
    cxc: cxc,
    codigoBarras: codigo,
    unidadesObjetivo: unidades,
    cajasObjetivo: cajas,
  );
}

List<CamionMock> buildBodegaMockCamiones() {
  final hinoProductos = <PickingProductoMock>[
    _p('h1', 'Bebidas', 'Coca Cola', 'Lata 350cc', 24, '7801234000001', 240, 10, _hinoId),
    _p('h2', 'Bebidas', 'Coca Cola', 'Botella 1.5L', 6, '7801234000002', 180, 30, _hinoId),
    _p('h3', 'Bebidas', 'Coca Cola', 'Zero Lata 350cc', 24, '7801234000003', 120, 5, _hinoId),
    _p('h4', 'Bebidas', 'Coca Cola', 'Sin azúcar 600ml', 12, '7801234000004', 144, 12, _hinoId),
    _p('h5', 'Bebidas', 'Pepsi', '1.5L', 6, '7801234000101', 96, 16, _hinoId),
    _p('h6', 'Bebidas', 'Agua mineral', '600ml', 12, '7801234000201', 120, 10, _hinoId),
    _p('h7', 'Bebidas', 'Jugo Watt\'s', 'Naranja 1L', 12, '7801234000301', 72, 6, _hinoId),
    _p('h8', 'Abarrotes', 'Arroz', '1 kg Tucapel', 20, '7801234100001', 200, 10, _hinoId),
    _p('h9', 'Abarrotes', 'Aceite', 'Maravilla 900ml', 12, '7801234100002', 60, 5, _hinoId),
    _p('h10', 'Abarrotes', 'Azúcar', 'Iansa 1kg', 10, '7801234100003', 100, 10, _hinoId),
    _p('h11', 'Abarrotes', 'Fideos', 'Largo #5 Carozzi', 20, '7801234100004', 200, 10, _hinoId),
    _p('h12', 'Lácteos', 'Leche', 'Sémidescremada 1L', 12, '7801234200001', 96, 8, _hinoId),
    _p('h13', 'Lácteos', 'Yogurt', 'Batido frutilla 155g', 8, '7801234200002', 64, 8, _hinoId),
    _p('h14', 'Lácteos', 'Mantequilla', '250g', 24, '7801234200003', 48, 2, _hinoId),
    _p('h15', 'Congelados', 'Hamburguesa', 'Res 4u', 10, '7801234300001', 40, 4, _hinoId),
    _p('h16', 'Congelados', 'Papas prefritas', '4 kg', 4, '7801234300002', 16, 4, _hinoId),
    _p('h17', 'Congelados', 'Vegetales mix', '1 kg', 12, '7801234300003', 48, 4, _hinoId),
    _p('h18', 'Bebidas', 'Sprite', 'Lata 350cc', 24, '7801234000401', 120, 5, _hinoId),
    _p('h19', 'Abarrotes', 'Sal', '1 kg', 20, '7801234100005', 40, 2, _hinoId),
    _p('h20', 'Lácteos', 'Queso', 'Gauda laminado 200g', 16, '7801234200004', 64, 4, _hinoId),
  ];

  final hyundaiProductos = <PickingProductoMock>[
    _p('y1', 'Bebidas', 'Coca Cola', 'Lata 350cc', 24, '7802234000001', 48, 2, _hyundaiId),
    _p('y2', 'Bebidas', 'Fanta', 'Naranja 2L', 8, '7802234000002', 32, 4, _hyundaiId),
    _p('y3', 'Abarrotes', 'Harina', '000 5kg', 4, '7802234100001', 20, 5, _hyundaiId),
    _p('y4', 'Lácteos', 'Leche', 'Entera 1L', 12, '7802234200001', 24, 2, _hyundaiId),
    _p('y5', 'Congelados', 'Helado', 'Vainilla 1L', 8, '7802234300001', 16, 2, _hyundaiId),
    _p('y6', 'Bebidas', 'Coca Cola', 'Botella 600ml', 12, '7802234000003', 36, 3, _hyundaiId),
    _p('y7', 'Abarrotes', 'Atún', 'Lomitos agua 170g', 24, '7802234100002', 48, 2, _hyundaiId),
    _p('y8', 'Lácteos', 'Crema', 'Chantilly 200g', 12, '7802234200002', 24, 2, _hyundaiId),
    _p('y9', 'Bebidas', 'Monster', 'Energy 473ml', 12, '7802234000004', 24, 2, _hyundaiId),
    _p('y10', 'Abarrotes', 'Conserva', 'Arvejas 400g', 24, '7802234100003', 48, 2, _hyundaiId),
  ];

  return [
    CamionMock(
      id: _hinoId,
      nombre: 'HINO 3',
      clientesCount: 12,
      montoTotalPesos: 5700000,
      productos: hinoProductos,
    ),
    CamionMock(
      id: _hyundaiId,
      nombre: 'HYUNDAI',
      clientesCount: 5,
      montoTotalPesos: 1500000,
      productos: hyundaiProductos,
    ),
  ];
}

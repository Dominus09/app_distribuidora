import '../models/chofer_cliente.dart';
import '../models/chofer_entrega_estado.dart';

/// Datos mock fijos (Quellón). 18 paradas; las 10 primeras ya entregadas (ejemplo de progreso).
List<ChoferCliente> buildChoferMockClientesSeed() {
  const nombres = <String>[
    'Comercial López',
    'Distribuidora Sur',
    'Almacén Central',
    'Mini Market El Mar',
    'Ferretería Costa',
    'Botillería Unión',
    'Supermercado 18',
    'Pescadería Don Tito',
    'Verdulería Los Lagos',
    'Panadería Amunátegui',
    'Abarrotes El Bosque',
    'Kiosco La Punta',
    'Comercial Norte',
    'Bazar Quellón',
    'Electrónica Sur',
    'Farmacia Salud +',
    'Restaurant El Muelle',
    'Casa de Empaques',
  ];
  const vendedores = <String>[
    'Juan Pérez',
    'María González',
    'Juan Pérez',
    'Pedro Soto',
    'María González',
    'Juan Pérez',
    'Ana Riquelme',
    'Pedro Soto',
    'María González',
    'Juan Pérez',
    'Ana Riquelme',
    'Pedro Soto',
    'Juan Pérez',
    'María González',
    'Ana Riquelme',
    'Pedro Soto',
    'Juan Pérez',
    'María González',
  ];

  const baseLat = -43.116;
  const baseLng = -73.616;

  return List<ChoferCliente>.generate(18, (i) {
    final orden = i + 1;
    final fila = i ~/ 6;
    final col = i % 6;
    final lat = baseLat + fila * 0.012 + col * 0.004;
    final lng = baseLng + col * 0.01 - fila * 0.006;
    final entregadoYa = orden <= 10;
    return ChoferCliente(
      id: 'chofer_$orden',
      nombreFantasia: nombres[i],
      ciudad: 'Quellón',
      direccion: 'Calle ${col + 1} #${100 + orden * 3}',
      lat: lat,
      lng: lng,
      estado: entregadoYa
          ? ChoferEntregaEstado.entregado
          : ChoferEntregaEstado.pendiente,
      telefono: '+5691122${i.toString().padLeft(4, '0')}',
      vendedor: vendedores[i],
      distanciaMetrosMock: 120 + orden * 28,
      ordenRuta: orden,
      documentosDia: orden.isEven
          ? ['Guía despacho ${4520 + i}', 'Factura copia']
          : ['Guía despacho ${4520 + i}'],
    );
  });
}

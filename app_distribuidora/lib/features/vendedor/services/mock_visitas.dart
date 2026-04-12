import '../models/visita.dart';
import '../models/visita_estado.dart';

/// Datos de demostración para la ruta del vendedor.
List<Visita> mockVisitasDelDia() {
  return [
    const Visita(
      id: '1',
      orden: 1,
      cliente: 'Distribuidora Norte S.A.',
      direccion: 'Av. Principal 1200, Quito',
      estado: VisitaEstado.pendiente,
    ),
    const Visita(
      id: '2',
      orden: 2,
      cliente: 'Mini Market El Sol',
      direccion: 'Calle Junín 45 y Amazonas',
      estado: VisitaEstado.pendiente,
    ),
    const Visita(
      id: '3',
      orden: 3,
      cliente: 'Depósito La Esquina',
      direccion: 'Av. 6 de Diciembre N32-14',
      estado: VisitaEstado.pendiente,
    ),
    const Visita(
      id: '4',
      orden: 4,
      cliente: 'Autoservicio 2000',
      direccion: 'Calle Guayaquil 210',
      estado: VisitaEstado.pendiente,
    ),
    const Visita(
      id: '5',
      orden: 5,
      cliente: 'Bodega San Francisco',
      direccion: 'Av. Occidental km 8.5',
      estado: VisitaEstado.pendiente,
    ),
    const Visita(
      id: '6',
      orden: 6,
      cliente: 'Carnicería El Chaco',
      direccion: 'Mercado Central, puesto 18',
      estado: VisitaEstado.pendiente,
    ),
    const Visita(
      id: '7',
      orden: 7,
      cliente: 'Tienda Don Pepe',
      direccion: 'Calle Bolívar S12-33',
      estado: VisitaEstado.pendiente,
    ),
    const Visita(
      id: '8',
      orden: 8,
      cliente: 'Super Ahorro',
      direccion: 'Av. Interoceánica, CC Condado',
      estado: VisitaEstado.pendiente,
    ),
    const Visita(
      id: '9',
      orden: 9,
      cliente: 'Abarrotes La Familia',
      direccion: 'Calle Río Coca E4-12',
      estado: VisitaEstado.pendiente,
    ),
    const Visita(
      id: '10',
      orden: 10,
      cliente: 'Punto de venta 24h',
      direccion: 'Av. Shyris N37-80',
      estado: VisitaEstado.pendiente,
    ),
    const Visita(
      id: '11',
      orden: 11,
      cliente: 'Mayorista Sur',
      direccion: 'Av. Morán Valverde 550',
      estado: VisitaEstado.pendiente,
    ),
    const Visita(
      id: '12',
      orden: 12,
      cliente: 'Retail Express',
      direccion: 'Av. República de El Salvador',
      estado: VisitaEstado.pendiente,
    ),
  ];
}

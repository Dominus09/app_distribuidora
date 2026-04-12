import 'dart:math';

import '../models/visita.dart';

/// Ruta del día, almacenamiento local simulado y utilidades (sin API).
class VendedorService {
  VendedorService();

  final _random = Random();
  int _actionSeq = 0;

  /// Copia en memoria que simula persistencia local entre pantallas (misma sesión).
  List<Visita>? _mockLocalStore;

  /// ID único por acción guardada (visitado / incidencia) para idempotencia al sincronizar.
  String generateLocalActionId() {
    _actionSeq++;
    return 'act_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}_$_actionSeq';
  }

  /// Simula escribir el estado de la ruta en disco local.
  void persistVisitas(List<Visita> visitas) {
    _mockLocalStore = List<Visita>.from(visitas);
  }

  /// Carga visitas persistidas o la ruta mock inicial.
  List<Visita> loadInitialRoute() {
    if (_mockLocalStore != null && _mockLocalStore!.isNotEmpty) {
      return List<Visita>.from(_mockLocalStore!);
    }
    return buildMockDayRoute();
  }

  /// Entre 8 y 12 clientes; coordenadas alrededor del mock de [LocationService].
  List<Visita> buildMockDayRoute() {
    const baseLat = -0.22985;
    const baseLon = -78.52495;
    const stepNear = 0.0009;
    const stepFar = 0.0035;

    return [
      Visita(
        id: 'v1',
        clienteNombre: 'Distribuidora Norte S.A.',
        direccion: 'Av. Principal 1200, Quito',
        orden: 1,
        estado: VisitaEstado.pendiente,
        latCliente: baseLat + stepNear * 0,
        lonCliente: baseLon,
      ),
      Visita(
        id: 'v2',
        clienteNombre: 'Mini Market El Sol',
        direccion: 'Calle Junín 45 y Amazonas',
        orden: 2,
        estado: VisitaEstado.pendiente,
        latCliente: baseLat + stepNear * 1,
        lonCliente: baseLon + stepNear * 0.5,
      ),
      Visita(
        id: 'v3',
        clienteNombre: 'Depósito La Esquina',
        direccion: 'Av. 6 de Diciembre N32-14',
        orden: 3,
        estado: VisitaEstado.pendiente,
        latCliente: baseLat + stepNear * 2,
        lonCliente: baseLon,
      ),
      Visita(
        id: 'v4',
        clienteNombre: 'Autoservicio 2000',
        direccion: 'Calle Guayaquil 210',
        orden: 4,
        estado: VisitaEstado.pendiente,
        latCliente: baseLat + stepNear * 0.5,
        lonCliente: baseLon + stepNear * 2,
      ),
      Visita(
        id: 'v5',
        clienteNombre: 'Bodega San Francisco',
        direccion: 'Av. Occidental km 8.5',
        orden: 5,
        estado: VisitaEstado.pendiente,
        latCliente: baseLat + stepFar,
        lonCliente: baseLon,
      ),
      Visita(
        id: 'v6',
        clienteNombre: 'Carnicería El Chaco',
        direccion: 'Mercado Central, puesto 18',
        orden: 6,
        estado: VisitaEstado.pendiente,
        latCliente: baseLat - stepFar,
        lonCliente: baseLon + stepFar,
      ),
      Visita(
        id: 'v7',
        clienteNombre: 'Tienda Don Pepe',
        direccion: 'Calle Bolívar S12-33',
        orden: 7,
        estado: VisitaEstado.pendiente,
        latCliente: baseLat + stepNear * 3,
        lonCliente: baseLon - stepNear,
      ),
      Visita(
        id: 'v8',
        clienteNombre: 'Super Ahorro',
        direccion: 'Av. Interoceánica, CC Condado',
        orden: 8,
        estado: VisitaEstado.pendiente,
        latCliente: baseLat + stepFar * 1.1,
        lonCliente: baseLon - stepFar * 0.8,
      ),
      Visita(
        id: 'v9',
        clienteNombre: 'Abarrotes La Familia',
        direccion: 'Calle Río Coca E4-12',
        orden: 9,
        estado: VisitaEstado.pendiente,
        latCliente: baseLat + stepNear * 0.3,
        lonCliente: baseLon + stepNear * 1.5,
      ),
      Visita(
        id: 'v10',
        clienteNombre: 'Retail Express',
        direccion: 'Av. República de El Salvador N94-12',
        orden: 10,
        estado: VisitaEstado.pendiente,
        latCliente: baseLat + stepNear * 2.2,
        lonCliente: baseLon + stepNear * 1.2,
      ),
    ];
  }
}

// Modelo de dominio de una parada de ruta (mock, sin API).

/// Estado operativo de la visita en terreno.
enum VisitaEstado {
  pendiente,
  visitado,
  incidencia,
}

/// Resultado de la validación por georreferencia (mock GPS / distancia).
enum ValidacionEstado {
  validado,
  fueraRango,
  sinGps,
  pendienteValidacion,
  offline,
}

/// Sincronización con backend (simulado).
enum SyncStatus {
  synced,
  pendingSync,
}

/// Tipos de incidencia reportables.
enum TipoIncidencia {
  localCerrado,
  sinStock,
  noCompra,
  fueraDeRuta,
  otros,
}

extension VisitaEstadoUi on VisitaEstado {
  String get label => switch (this) {
        VisitaEstado.pendiente => 'Pendiente',
        VisitaEstado.visitado => 'Visitado',
        VisitaEstado.incidencia => 'Incidencia',
      };

  /// Color de semáforo en listas y tarjetas.
  int get toneColorValue => switch (this) {
        VisitaEstado.pendiente => 0xFFF9A825,
        VisitaEstado.visitado => 0xFF2E7D32,
        VisitaEstado.incidencia => 0xFFC62828,
      };
}

extension ValidacionEstadoUi on ValidacionEstado {
  String get label => switch (this) {
        ValidacionEstado.validado => 'Validado (≤ 300 m)',
        ValidacionEstado.fueraRango => 'Fuera de rango (> 300 m)',
        ValidacionEstado.sinGps => 'Sin GPS',
        ValidacionEstado.pendienteValidacion => 'Pendiente de validación',
        ValidacionEstado.offline => 'Sin conexión',
      };
}

extension SyncStatusUi on SyncStatus {
  String get label => switch (this) {
        SyncStatus.synced => 'Sincronizado',
        SyncStatus.pendingSync => 'Pendiente de envío',
      };
}

extension TipoIncidenciaUi on TipoIncidencia {
  String get label => switch (this) {
        TipoIncidencia.localCerrado => 'Local cerrado',
        TipoIncidencia.sinStock => 'Sin stock',
        TipoIncidencia.noCompra => 'No compra',
        TipoIncidencia.fueraDeRuta => 'Fuera de ruta',
        TipoIncidencia.otros => 'Otros',
      };
}

class Visita {
  const Visita({
    required this.id,
    required this.clienteNombre,
    required this.direccion,
    required this.orden,
    required this.estado,
    required this.latCliente,
    required this.lonCliente,
    this.tipoIncidencia,
    this.observacion,
    this.conCompra,
    this.latVisita,
    this.lonVisita,
    this.fechaHoraVisita,
    this.distanciaMetros,
    this.validacionEstado = ValidacionEstado.pendienteValidacion,
    this.fotoPath,
    this.syncStatus = SyncStatus.synced,
    this.localActionId,
  });

  final String id;
  final String clienteNombre;
  final String direccion;
  final int orden;
  final VisitaEstado estado;
  final TipoIncidencia? tipoIncidencia;
  final String? observacion;
  final bool? conCompra;
  final double latCliente;
  final double lonCliente;
  final double? latVisita;
  final double? lonVisita;
  final DateTime? fechaHoraVisita;
  final double? distanciaMetros;
  final ValidacionEstado validacionEstado;
  final String? fotoPath;
  final SyncStatus syncStatus;
  final String? localActionId;

  Visita copyWith({
    String? id,
    String? clienteNombre,
    String? direccion,
    int? orden,
    VisitaEstado? estado,
    Object? tipoIncidencia = _sentinel,
    Object? observacion = _sentinel,
    Object? conCompra = _sentinel,
    double? latCliente,
    double? lonCliente,
    Object? latVisita = _sentinel,
    Object? lonVisita = _sentinel,
    Object? fechaHoraVisita = _sentinel,
    Object? distanciaMetros = _sentinel,
    ValidacionEstado? validacionEstado,
    Object? fotoPath = _sentinel,
    SyncStatus? syncStatus,
    Object? localActionId = _sentinel,
  }) {
    return Visita(
      id: id ?? this.id,
      clienteNombre: clienteNombre ?? this.clienteNombre,
      direccion: direccion ?? this.direccion,
      orden: orden ?? this.orden,
      estado: estado ?? this.estado,
      tipoIncidencia: tipoIncidencia == _sentinel
          ? this.tipoIncidencia
          : tipoIncidencia as TipoIncidencia?,
      observacion:
          observacion == _sentinel ? this.observacion : observacion as String?,
      conCompra: conCompra == _sentinel ? this.conCompra : conCompra as bool?,
      latCliente: latCliente ?? this.latCliente,
      lonCliente: lonCliente ?? this.lonCliente,
      latVisita: latVisita == _sentinel ? this.latVisita : latVisita as double?,
      lonVisita: lonVisita == _sentinel ? this.lonVisita : lonVisita as double?,
      fechaHoraVisita: fechaHoraVisita == _sentinel
          ? this.fechaHoraVisita
          : fechaHoraVisita as DateTime?,
      distanciaMetros: distanciaMetros == _sentinel
          ? this.distanciaMetros
          : distanciaMetros as double?,
      validacionEstado: validacionEstado ?? this.validacionEstado,
      fotoPath: fotoPath == _sentinel ? this.fotoPath : fotoPath as String?,
      syncStatus: syncStatus ?? this.syncStatus,
      localActionId: localActionId == _sentinel
          ? this.localActionId
          : localActionId as String?,
    );
  }

  static const Object _sentinel = _Sentinel();
}

class _Sentinel {
  const _Sentinel();
}

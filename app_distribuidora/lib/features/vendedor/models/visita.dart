// Modelo de dominio de una parada de ruta (API + almacenamiento local).
// Contrato alineado con OpenAPI: VisitaCreate, VisitaResponse (Quillotana Analytics API).

/// Estado operativo de la visita en terreno.
enum VisitaEstado { pendiente, visitado, incidencia }

/// Resultado de la validación por georreferencia.
enum ValidacionEstado {
  validado,
  fueraRango,
  sinGps,
  pendienteValidacion,
  offline,
}

/// Sincronización con backend y estados locales de cola.
/// `syncing` y `syncError` son solo cliente; en API se envían como `pending_sync`.
enum SyncStatus { synced, pendingSync, syncing, syncError }

/// Tipos de incidencia reportables.
enum TipoIncidencia {
  localCerrado,
  sinStock,
  noCompra,
  fueraDeRuta,
  otros,

  /// Contacto remoto; sin validación GPS, evidencia obligatoria.
  atencionTelefonica,
}

extension VisitaEstadoUi on VisitaEstado {
  String get label => switch (this) {
    VisitaEstado.pendiente => 'Pendiente',
    VisitaEstado.visitado => 'Visitado',
    VisitaEstado.incidencia => 'Incidencia',
  };

  /// Colores de estado en terreno: pendiente amarillo, visitado azul marca, incidencia rojo marca.
  int get toneColorValue => switch (this) {
    VisitaEstado.pendiente => 0xFFFFC107,
    VisitaEstado.visitado => 0xFF1F3A5F,
    VisitaEstado.incidencia => 0xFFE10600,
  };

  /// Valores del enum en FastAPI (`VisitaCreate` / `VisitaResponse`).
  String get apiValue => switch (this) {
    VisitaEstado.pendiente => 'pendiente',
    VisitaEstado.visitado => 'visitado',
    VisitaEstado.incidencia => 'incidencia',
  };
}

extension ValidacionEstadoUi on ValidacionEstado {
  String get label => switch (this) {
    ValidacionEstado.validado => 'Validado (≤ 500 m)',
    ValidacionEstado.fueraRango => 'Fuera de rango (> 500 m)',
    ValidacionEstado.sinGps => 'Sin GPS',
    ValidacionEstado.pendienteValidacion => 'Pendiente de validación',
    ValidacionEstado.offline => 'Sin conexión',
  };

  String get apiValue => switch (this) {
    ValidacionEstado.validado => 'validado',
    ValidacionEstado.fueraRango => 'fuera_rango',
    ValidacionEstado.sinGps => 'sin_gps',
    ValidacionEstado.pendienteValidacion => 'pendiente_validacion',
    ValidacionEstado.offline => 'offline',
  };
}

extension SyncStatusUi on SyncStatus {
  String get label => switch (this) {
    SyncStatus.synced => 'Sincronizado',
    SyncStatus.pendingSync => 'Pendiente de envío',
    SyncStatus.syncing => 'Sincronizando…',
    SyncStatus.syncError => 'Error de sincronización',
  };

  /// Valor persistido en caché local (`toJson`).
  String get persistValue => switch (this) {
    SyncStatus.synced => 'synced',
    SyncStatus.pendingSync => 'pending_sync',
    SyncStatus.syncing => 'syncing',
    SyncStatus.syncError => 'sync_error',
  };

  /// Valor enviado al backend en `VisitaCreate` (solo `synced` / `pending_sync`).
  String get apiValue => switch (this) {
    SyncStatus.synced => 'synced',
    SyncStatus.pendingSync => 'pending_sync',
    SyncStatus.syncing => 'pending_sync',
    SyncStatus.syncError => 'pending_sync',
  };

  bool get necesitaPushRemoto =>
      this == SyncStatus.pendingSync ||
      this == SyncStatus.syncError ||
      this == SyncStatus.syncing;
}

extension TipoIncidenciaUi on TipoIncidencia {
  String get label => switch (this) {
    TipoIncidencia.localCerrado => 'Local cerrado',
    TipoIncidencia.sinStock => 'Sin stock',
    TipoIncidencia.noCompra => 'No compra',
    TipoIncidencia.fueraDeRuta => 'Fuera de ruta',
    TipoIncidencia.otros => 'Otros',
    TipoIncidencia.atencionTelefonica => 'Atención telefónica',
  };

  /// FastAPI enum en `VisitaCreate`: textos con espacio, no snake_case.
  String get apiValue => switch (this) {
    TipoIncidencia.localCerrado => 'local cerrado',
    TipoIncidencia.sinStock => 'sin stock',
    TipoIncidencia.noCompra => 'no compra',
    TipoIncidencia.fueraDeRuta => 'fuera de ruta',
    TipoIncidencia.otros => 'otros',
    TipoIncidencia.atencionTelefonica => 'atencion telefonica',
  };
}

class Visita {
  const Visita({
    required this.id,
    this.rutaId,
    this.clienteId,
    required this.clienteNombre,
    this.nombreFantasia,
    required this.direccion,
    this.comuna,
    this.rutClean,
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

  /// Identificador de fila (`VisitaResponse.id` int en API → string en app).
  final String id;

  /// Ruta del día (`VisitaCreate.ruta_id` / `VisitaResponse.ruta_id`).
  final int? rutaId;

  /// Identificador de cliente en ERP (`VisitaCreate.cliente_id` es string en API).
  final String? clienteId;
  final String clienteNombre;

  /// Si la API envía `nombre_fantasia`, se usa en mapa / UI cuando aplica.
  final String? nombreFantasia;
  final String direccion;

  /// Comuna del cliente (`comuna` en API).
  final String? comuna;

  /// RUT sin formato (`rut_clean` en API).
  final String? rutClean;

  /// Título en mapa: prioriza `nombre_fantasia`, si no `clienteNombre`.
  String get tituloMapaCliente {
    final n = nombreFantasia?.trim();
    if (n != null && n.isNotEmpty) return n;
    return clienteNombre;
  }

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

  /// Evidencia local o URL remota; en POST se envía como `foto_url`.
  final String? fotoPath;
  final SyncStatus syncStatus;
  final String? localActionId;

  /// `id` numérico de la fila en backend (GET ruta). Sin esto no se debe POST (evita duplicados).
  bool get tieneIdBackend {
    final t = id.trim();
    if (t.isEmpty) return false;
    final n = int.tryParse(t);
    return n != null && n >= 1;
  }

  /// `id` como entero para el JSON de API, o `null` si no es válido.
  int? get idBackendEntero {
    final n = int.tryParse(id.trim());
    if (n == null || n < 1) return null;
    return n;
  }

  /// True si se puede armar el cuerpo para POST /visitas o /visitas/sync (misma visita, no alta nueva).
  bool get puedeEnviarseAlBackend =>
      tieneIdBackend &&
      localActionId != null &&
      localActionId!.isNotEmpty &&
      rutaId != null &&
      rutaId! >= 1 &&
      orden >= 1;

  /// Solo paradas pendientes admiten marcar visitado / incidencia de nuevo.
  bool get puedeEditarse => estado == VisitaEstado.pendiente;

  factory Visita.fromJson(Map<String, dynamic> json) {
    final idVal = json['id'];
    final id = idVal == null ? '' : idVal.toString();

    return Visita(
      id: id,
      rutaId: _parseInt(json['ruta_id']),
      clienteId: _parseClienteId(json['cliente_id']),
      clienteNombre: _parseClienteNombre(json),
      nombreFantasia: _str(json, 'nombre_fantasia'),
      direccion: _parseDireccion(json),
      comuna: _str(json, 'comuna'),
      rutClean: _str(json, 'rut_clean', 'rutClean'),
      orden: _parseInt(json['orden_ruta']) ?? _parseInt(json['orden']) ?? 0,
      estado: _parseEstado(_str(json, 'estado')),
      latCliente: _parseCoord(json['lat_cliente']) ?? 0,
      lonCliente: _parseCoord(json['lon_cliente']) ?? 0,
      tipoIncidencia: _parseTipoIncidencia(_normTipoIncidenciaRaw(json)),
      observacion: _str(json, 'observacion'),
      conCompra: _parseBool(json['con_compra']),
      latVisita: _parseCoord(json['lat_visita']),
      lonVisita: _parseCoord(json['lon_visita']),
      fechaHoraVisita: _parseDateTime(json['fecha_hora_visita']),
      distanciaMetros: _parseCoord(json['distancia_metros']),
      validacionEstado: _parseValidacion(_str(json, 'validacion_estado')),
      fotoPath: _str(json, 'foto_url', 'foto_path'),
      syncStatus: _parseSyncStatus(_str(json, 'sync_status')),
      localActionId: _str(json, 'local_action_id'),
    );
  }

  /// JSON completo para caché local (SharedPreferences). Incluye campos de UI.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (rutaId != null) 'ruta_id': rutaId,
      if (clienteId != null) 'cliente_id': clienteId,
      'cliente_nombre': clienteNombre,
      if (nombreFantasia != null) 'nombre_fantasia': nombreFantasia,
      'direccion': direccion,
      if (comuna != null) 'comuna': comuna,
      if (rutClean != null) 'rut_clean': rutClean,
      'orden_ruta': orden,
      'estado': estado.apiValue,
      if (tipoIncidencia != null) 'tipo_incidencia': tipoIncidencia!.apiValue,
      if (observacion != null) 'observacion': observacion,
      if (conCompra != null) 'con_compra': conCompra,
      'lat_cliente': latCliente,
      'lon_cliente': lonCliente,
      if (latVisita != null) 'lat_visita': latVisita,
      if (lonVisita != null) 'lon_visita': lonVisita,
      if (fechaHoraVisita != null)
        'fecha_hora_visita': _fechaHoraParaJson(fechaHoraVisita!),
      if (distanciaMetros != null) 'distancia_metros': distanciaMetros,
      'validacion_estado': validacionEstado.apiValue,
      if (fotoPath != null) 'foto_path': fotoPath,
      'sync_status': syncStatus.persistValue,
      if (localActionId != null) 'local_action_id': localActionId,
    };
  }

  /// Cuerpo exacto de `VisitaCreate` (POST /visitas y elementos de /visitas/sync).
  /// Lanza [StateError] si faltan campos obligatorios del contrato OpenAPI.
  Map<String, dynamic> toJsonForApiCreate() {
    final lid = localActionId;
    final rid = rutaId;
    if (lid == null || lid.isEmpty) {
      throw StateError('Visita.toJsonForApiCreate: falta local_action_id');
    }
    if (rid == null || rid < 1) {
      throw StateError('Visita.toJsonForApiCreate: falta ruta_id válido');
    }
    if (orden < 1) {
      throw StateError('Visita.toJsonForApiCreate: orden_ruta debe ser >= 1');
    }

    final cid = (clienteId != null && clienteId!.trim().isNotEmpty)
        ? clienteId!.trim()
        : id.trim();
    if (cid.isEmpty) {
      throw StateError('Visita.toJsonForApiCreate: falta cliente_id');
    }

    final vid = idBackendEntero;
    if (vid == null) {
      throw StateError(
        'Visita.toJsonForApiCreate: falta id de visita del backend (evita crear duplicados)',
      );
    }

    final out = <String, dynamic>{
      'id': vid,
      'local_action_id': lid,
      'ruta_id': rid,
      'cliente_id': cid,
      'orden_ruta': orden,
      'estado': estado.apiValue,
      'sync_status': syncStatus.apiValue,
      'lat_cliente': latCliente,
      'lon_cliente': lonCliente,
    };

    if (tipoIncidencia != null) {
      out['tipo_incidencia'] = tipoIncidencia!.apiValue;
    }
    if (observacion != null && observacion!.trim().isNotEmpty) {
      out['observacion'] = observacion!.trim();
    }
    if (conCompra != null) {
      out['con_compra'] = conCompra;
    }
    if (fotoPath != null && fotoPath!.trim().isNotEmpty) {
      out['foto_url'] = fotoPath!.trim();
    }
    if (latVisita != null) {
      out['lat_visita'] = latVisita;
    }
    if (lonVisita != null) {
      out['lon_visita'] = lonVisita;
    }
    if (fechaHoraVisita != null) {
      out['fecha_hora_visita'] = _fechaHoraParaJson(fechaHoraVisita!);
    }

    return out;
  }

  Visita copyWith({
    String? id,
    Object? rutaId = _sentinel,
    Object? clienteId = _sentinel,
    String? clienteNombre,
    Object? nombreFantasia = _sentinel,
    String? direccion,
    Object? comuna = _sentinel,
    Object? rutClean = _sentinel,
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
      rutaId: rutaId == _sentinel ? this.rutaId : rutaId as int?,
      clienteId: clienteId == _sentinel ? this.clienteId : clienteId as String?,
      clienteNombre: clienteNombre ?? this.clienteNombre,
      nombreFantasia: nombreFantasia == _sentinel
          ? this.nombreFantasia
          : nombreFantasia as String?,
      direccion: direccion ?? this.direccion,
      comuna: comuna == _sentinel ? this.comuna : comuna as String?,
      rutClean: rutClean == _sentinel ? this.rutClean : rutClean as String?,
      orden: orden ?? this.orden,
      estado: estado ?? this.estado,
      tipoIncidencia: tipoIncidencia == _sentinel
          ? this.tipoIncidencia
          : tipoIncidencia as TipoIncidencia?,
      observacion: observacion == _sentinel
          ? this.observacion
          : observacion as String?,
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

/// ISO 8601 en UTC (formato `date-time` de OpenAPI).
String _fechaHoraParaJson(DateTime d) => d.toUtc().toIso8601String();

String? _str(Map<String, dynamic> json, String snake, [String? camel]) {
  final v = json[snake] ?? (camel != null ? json[camel] : null);
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

String? _normTipoIncidenciaRaw(Map<String, dynamic> json) {
  final v = json['tipo_incidencia'];
  if (v == null) return null;
  return v.toString().trim().toLowerCase().replaceAll('_', ' ');
}

String _parseClienteNombre(Map<String, dynamic> json) {
  for (final k in [
    'cliente_nombre',
    'nombre_cliente',
    'nombre_fantasia',
    'razon_social',
    'nombre',
  ]) {
    final s = _str(json, k);
    if (s != null && s.isNotEmpty) return s;
  }
  return '';
}

String _parseDireccion(Map<String, dynamic> json) {
  for (final k in ['direccion', 'domicilio', 'direccion_cliente']) {
    final s = _str(json, k);
    if (s != null && s.isNotEmpty) return s;
  }
  return '';
}

String? _parseClienteId(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int? _parseInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

bool? _parseBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return null;
}

/// Coordenadas y distancias: API puede devolver `number` o `string` decimal.
double? _parseCoord(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

DateTime? _parseDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

VisitaEstado _parseEstado(String? s) {
  switch (s) {
    case 'visitado':
      return VisitaEstado.visitado;
    case 'incidencia':
      return VisitaEstado.incidencia;
    default:
      return VisitaEstado.pendiente;
  }
}

ValidacionEstado _parseValidacion(String? s) {
  switch (s) {
    case 'fuera_rango':
      return ValidacionEstado.fueraRango;
    case 'sin_gps':
      return ValidacionEstado.sinGps;
    case 'pendiente_validacion':
      return ValidacionEstado.pendienteValidacion;
    case 'offline':
      return ValidacionEstado.offline;
    case 'validado':
      return ValidacionEstado.validado;
    default:
      return ValidacionEstado.pendienteValidacion;
  }
}

SyncStatus _parseSyncStatus(String? s) {
  if (s == null || s.isEmpty) return SyncStatus.synced;
  final n = s.trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
  if (n == 'pending_sync') return SyncStatus.pendingSync;
  if (n == 'syncing') return SyncStatus.syncing;
  if (n == 'sync_error' || n == 'syncerror' || n == 'error_sync') {
    return SyncStatus.syncError;
  }
  if (n == 'synced') return SyncStatus.synced;
  return SyncStatus.synced;
}

TipoIncidencia? _parseTipoIncidencia(String? s) {
  if (s == null || s.isEmpty) return null;
  switch (s) {
    case 'local cerrado':
      return TipoIncidencia.localCerrado;
    case 'sin stock':
      return TipoIncidencia.sinStock;
    case 'no compra':
      return TipoIncidencia.noCompra;
    case 'fuera de ruta':
      return TipoIncidencia.fueraDeRuta;
    case 'otros':
      return TipoIncidencia.otros;
    case 'atencion telefonica':
    case 'atención telefonica':
      return TipoIncidencia.atencionTelefonica;
    default:
      return null;
  }
}

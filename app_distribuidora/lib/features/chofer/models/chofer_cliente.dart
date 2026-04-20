import 'chofer_entrega_estado.dart';
import 'tipo_incidencia_chofer.dart';

/// Parada de entrega chofer. [ordenRuta] y [distanciaMetrosMock] quedan listos para sustituir por datos ORS/backend.
class ChoferCliente {
  const ChoferCliente({
    required this.id,
    required this.nombreFantasia,
    required this.ciudad,
    required this.direccion,
    required this.lat,
    required this.lng,
    required this.estado,
    required this.telefono,
    required this.vendedor,
    required this.distanciaMetrosMock,
    required this.ordenRuta,
    required this.documentosDia,
    this.incidenciaTipo,
    this.observacionIncidencia,
  });

  final String id;
  final String nombreFantasia;
  final String ciudad;
  final String direccion;
  final double lat;
  final double lng;
  final ChoferEntregaEstado estado;
  final String telefono;
  final String vendedor;
  /// Referencia mock; con ORS vendrá desde backend ordenado.
  final int distanciaMetrosMock;
  /// Orden de visita en ruta (1 = primero). No se recalcula ruta en Flutter.
  final int ordenRuta;
  final List<String> documentosDia;
  final TipoIncidenciaChofer? incidenciaTipo;
  final String? observacionIncidencia;

  bool get esPendiente => estado == ChoferEntregaEstado.pendiente;

  ChoferCliente conEstadoEntregado() {
    return ChoferCliente(
      id: id,
      nombreFantasia: nombreFantasia,
      ciudad: ciudad,
      direccion: direccion,
      lat: lat,
      lng: lng,
      estado: ChoferEntregaEstado.entregado,
      telefono: telefono,
      vendedor: vendedor,
      distanciaMetrosMock: distanciaMetrosMock,
      ordenRuta: ordenRuta,
      documentosDia: documentosDia,
      incidenciaTipo: null,
      observacionIncidencia: null,
    );
  }

  ChoferCliente conIncidencia({
    required TipoIncidenciaChofer tipo,
    String? observacion,
  }) {
    final o = observacion?.trim();
    return ChoferCliente(
      id: id,
      nombreFantasia: nombreFantasia,
      ciudad: ciudad,
      direccion: direccion,
      lat: lat,
      lng: lng,
      estado: ChoferEntregaEstado.incidencia,
      telefono: telefono,
      vendedor: vendedor,
      distanciaMetrosMock: distanciaMetrosMock,
      ordenRuta: ordenRuta,
      documentosDia: documentosDia,
      incidenciaTipo: tipo,
      observacionIncidencia: (o == null || o.isEmpty) ? null : o,
    );
  }
}

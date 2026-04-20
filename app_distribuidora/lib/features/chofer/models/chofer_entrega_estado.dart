/// Estado de entrega en ruta chofer (mock; mismo contrato conceptual que usará el backend).
enum ChoferEntregaEstado {
  pendiente,
  entregado,
  incidencia,
}

extension ChoferEntregaEstadoUi on ChoferEntregaEstado {
  String get label => switch (this) {
        ChoferEntregaEstado.pendiente => 'Pendiente',
        ChoferEntregaEstado.entregado => 'Entregado',
        ChoferEntregaEstado.incidencia => 'Incidencia',
      };
}

import '../models/visita.dart';

/// Orden solo para UI: pendientes primero (`orden` ASC), luego visitado/incidencia (`orden` ASC).
/// No altera el orden en backend ni el orden almacenado en la lista fuente.
List<Visita> visitasOrdenVisualLista(List<Visita> visitas) {
  int byOrden(Visita a, Visita b) => a.orden.compareTo(b.orden);
  final pendientes = visitas
      .where((v) => v.estado == VisitaEstado.pendiente)
      .toList()
    ..sort(byOrden);
  final gestionadas = visitas
      .where((v) => v.estado != VisitaEstado.pendiente)
      .toList()
    ..sort(byOrden);
  return [...pendientes, ...gestionadas];
}

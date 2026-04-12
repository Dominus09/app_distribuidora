import 'visita_estado.dart';

/// Parada de ruta (mock; sin API).
class Visita {
  const Visita({
    required this.id,
    required this.orden,
    required this.cliente,
    required this.direccion,
    required this.estado,
    this.observaciones = '',
  });

  final String id;
  final int orden;
  final String cliente;
  final String direccion;
  final VisitaEstado estado;
  final String observaciones;

  Visita copyWith({
    String? id,
    int? orden,
    String? cliente,
    String? direccion,
    VisitaEstado? estado,
    String? observaciones,
  }) {
    return Visita(
      id: id ?? this.id,
      orden: orden ?? this.orden,
      cliente: cliente ?? this.cliente,
      direccion: direccion ?? this.direccion,
      estado: estado ?? this.estado,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}

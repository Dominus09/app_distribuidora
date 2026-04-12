import 'package:flutter/material.dart';

/// Estado operativo de una parada en ruta.
enum VisitaEstado {
  pendiente,
  visitado,
  incidencia,
}

extension VisitaEstadoX on VisitaEstado {
  String get label => switch (this) {
        VisitaEstado.pendiente => 'Pendiente',
        VisitaEstado.visitado => 'Visitado',
        VisitaEstado.incidencia => 'Incidencia',
      };

  /// Semáforo operativo (Material-friendly).
  Color get indicatorColor => switch (this) {
        VisitaEstado.pendiente => const Color(0xFFF9A825),
        VisitaEstado.visitado => const Color(0xFF2E7D32),
        VisitaEstado.incidencia => const Color(0xFFC62828),
      };
}

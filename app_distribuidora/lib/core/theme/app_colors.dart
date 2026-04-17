import 'package:flutter/material.dart';

/// Identidad corporativa (colores del logo).
abstract final class AppColors {
  static const Color primaryRed = Color(0xFFE10600);
  static const Color secondaryBlue = Color(0xFF1F3A5F);
  static const Color surface = Color(0xFFFFFFFF);

  /// Texto / iconos sobre botón primario (rojo).
  static const Color onPrimaryWhite = Color(0xFFFFFFFF);

  /// Borde lateral y acentos de estado **pendiente** (amarillo).
  static const Color estadoPendiente = Color(0xFFFFC107);

  /// Texto principal sobre fondos claros (azul marca, no negro puro).
  static const Color textPrimary = secondaryBlue;
}

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tema Material 3 alineado a la identidad corporativa (rojo, azul, blanco).
abstract final class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryRed,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primaryRed,
      onPrimary: AppColors.onPrimaryWhite,
      primaryContainer: const Color(0xFFFFE4E0),
      onPrimaryContainer: const Color(0xFF5C0D00),
      secondary: AppColors.secondaryBlue,
      onSecondary: AppColors.onPrimaryWhite,
      secondaryContainer: const Color(0xFFE8EEF4),
      onSecondaryContainer: AppColors.secondaryBlue,
      tertiary: AppColors.secondaryBlue,
      onTertiary: AppColors.onPrimaryWhite,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: const Color(0xFF5A6572),
      error: const Color(0xFFB3261E),
      onError: AppColors.onPrimaryWhite,
      outline: AppColors.secondaryBlue.withValues(alpha: 0.35),
      outlineVariant: AppColors.secondaryBlue.withValues(alpha: 0.18),
      shadow: AppColors.secondaryBlue.withValues(alpha: 0.18),
      scrim: const Color(0x66000000),
      surfaceTint: Colors.transparent,
    );

    final radius = BorderRadius.circular(12);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.surface,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.secondaryBlue,
        surfaceTintColor: Colors.transparent,
        shadowColor: AppColors.secondaryBlue.withValues(alpha: 0.08),
        iconTheme: const IconThemeData(color: AppColors.primaryRed, size: 24),
        actionsIconTheme: const IconThemeData(color: AppColors.primaryRed),
        titleTextStyle: const TextStyle(
          color: AppColors.secondaryBlue,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 2,
        shadowColor: AppColors.secondaryBlue.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryRed,
          foregroundColor: AppColors.onPrimaryWhite,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryRed,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.primaryRed, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondaryBlue,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        border: OutlineInputBorder(borderRadius: radius),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: AppColors.secondaryBlue.withValues(alpha: 0.25),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: AppColors.secondaryBlue, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.secondaryBlue.withValues(alpha: 0.12),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryRed,
        linearTrackColor: Color(0xFFE8EEF4),
      ),
    );
  }

  /// Misma base clara: evita fondos oscuros si el sistema pide modo oscuro.
  static ThemeData dark() => light();
}

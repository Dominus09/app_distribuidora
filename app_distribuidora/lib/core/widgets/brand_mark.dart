import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Marca gráfica simplificada (rojo + azul). Sustituir por [Image.asset] si agregas `assets/branding/logo.png`.
class BrandLogoMark extends StatelessWidget {
  const BrandLogoMark({super.key, this.height = 40});

  final double height;

  @override
  Widget build(BuildContext context) {
    final stripe = height * 0.12;
    final blockW = height * 0.55;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: stripe.clamp(4.0, 8.0),
          height: height,
          decoration: BoxDecoration(
            color: AppColors.primaryRed,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        SizedBox(width: height * 0.14),
        Container(
          width: blockW,
          height: height * 0.88,
          decoration: BoxDecoration(
            color: AppColors.secondaryBlue,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
    );
  }
}

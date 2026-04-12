import 'package:flutter/material.dart';

import '../models/visita.dart';
import '../models/visita_estado.dart';

/// Tarjeta de parada con acciones rápidas (sin pantalla intermedia).
class VisitaRutaCard extends StatelessWidget {
  const VisitaRutaCard({
    super.key,
    required this.visita,
    required this.onVisited,
    required this.onIncidencia,
    required this.onTap,
  });

  final Visita visita;
  final VoidCallback onVisited;
  final VoidCallback onIncidencia;
  final VoidCallback onTap;

  void _openMaps() {
    // ignore: avoid_print
    print('Open maps for ${visita.cliente}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = visita.estado.indicatorColor;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  '${visita.orden}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            visita.cliente,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            visita.estado.label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: c,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            visita.direccion,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _QuickActionButton(
                          icon: Icons.check_circle_outline,
                          label: 'Visitado',
                          color: const Color(0xFF2E7D32),
                          onPressed: onVisited,
                        ),
                        _QuickActionButton(
                          icon: Icons.warning_amber_rounded,
                          label: 'Incidencia',
                          color: const Color(0xFFC62828),
                          onPressed: onIncidencia,
                        ),
                        _QuickActionButton(
                          icon: Icons.navigation_outlined,
                          label: 'Navegar',
                          color: theme.colorScheme.primary,
                          onPressed: _openMaps,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: 0.12),
      ),
    );
  }
}

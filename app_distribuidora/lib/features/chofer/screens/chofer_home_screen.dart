import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/auth_navigation.dart';
import '../../auth/services/auth_service.dart';
import '../data/chofer_mock_repository.dart';
import '../utils/chofer_launchers.dart';
import '../widgets/chofer_mapa_ruta_mock.dart';
import 'chofer_clientes_screen.dart';

/// Home mock chofer: resumen, mapa, accesos y ruta Google sin backend.
class ChoferHomeScreen extends StatelessWidget {
  const ChoferHomeScreen({super.key});

  static String _fechaLarga() {
    final n = DateTime.now();
    const meses = <String>[
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${n.day} de ${meses[n.month - 1]} de ${n.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ChoferMockRepository.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chofer'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await DistribuidoraAuthService().logout();
              if (!context.mounted) return;
              replaceWithDistribuidoraLogin(context);
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final total = repo.total;
          final hechos = repo.completados;
          final pct = repo.progreso01;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Text(
                'Hola, ${ChoferMockRepository.choferNombreDisplay} 👋',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _fechaLarga(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ruta de hoy: ${ChoferMockRepository.rutaNombreHoy}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Resumen',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _MiniStat(
                    label: 'Clientes',
                    value: '$total',
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(width: 12),
                  _MiniStat(
                    label: 'Progreso',
                    value: '$hechos/$total',
                    color: AppColors.secondaryBlue,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: total == 0 ? 0 : pct,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: AppColors.secondaryBlue,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Mapa (pendientes)',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 8),
              const ChoferMapaRutaMock(),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const ChoferClientesScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.list_alt_outlined, size: 20),
                label: const Text('Ver lista de clientes'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  final c = repo.masCercanoPendiente();
                  if (c == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No hay pendientes'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  unawaited(launchGoogleMapsDirDestino(c.lat, c.lng));
                },
                icon: const Icon(Icons.near_me_outlined, size: 20),
                label: const Text('Ir al más cercano'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () {
                  final pts = repo
                      .pendientesOrdenRuta()
                      .map((e) => (lat: e.lat, lng: e.lng))
                      .toList();
                  if (pts.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No hay pendientes para armar la ruta'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  unawaited(launchGoogleMapsDirSecuencia(pts));
                },
                icon: const Icon(Icons.route_outlined, size: 20),
                label: const Text('Ver ruta completa (Google Maps)'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                  backgroundColor: AppColors.secondaryBlue,
                  foregroundColor: AppColors.onPrimaryWhite,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

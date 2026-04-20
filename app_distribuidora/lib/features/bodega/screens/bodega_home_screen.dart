import 'package:flutter/material.dart';

import '../../auth/auth_navigation.dart';
import '../../auth/services/auth_service.dart';
import '../data/bodega_mock_repository.dart';
import '../widgets/camion_card.dart';
import 'picking_screen.dart';

/// Home bodega: camiones del día y acceso a picking (mock).
class BodegaHomeScreen extends StatelessWidget {
  const BodegaHomeScreen({super.key, this.operadorNombre = 'Belén'});

  final String operadorNombre;

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
    final repo = BodegaMockRepository.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bodega'),
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
          final nCamiones = repo.camiones.length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Text(
                'Hola, $operadorNombre 👋',
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
              const SizedBox(height: 8),
              Text(
                'Camiones a cargar hoy: $nCamiones',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Camiones',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 12),
              for (final c in repo.camiones) ...[
                CamionCard(
                  camion: c,
                  onIniciarPicking: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => PickingScreen(camionId: c.id),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ],
          );
        },
      ),
    );
  }
}

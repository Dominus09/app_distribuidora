import 'package:flutter/material.dart';

import '../models/camion_mock.dart';
import '../utils/bodega_format.dart';

/// Tarjeta grande tipo dashboard para iniciar picking de un camión.
class CamionCard extends StatelessWidget {
  const CamionCard({
    super.key,
    required this.camion,
    required this.onIniciarPicking,
  });

  final CamionMock camion;
  final VoidCallback onIniciarPicking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 3,
      shadowColor: scheme.primary.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onIniciarPicking,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_shipping_rounded, size: 36, color: scheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      camion.nombre,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _StatRow(
                icon: Icons.groups_outlined,
                texto: '${camion.clientesCount} clientes',
              ),
              const SizedBox(height: 8),
              _StatRow(
                icon: Icons.payments_outlined,
                texto: formatearPesosChilenos(camion.montoTotalPesos),
              ),
              const SizedBox(height: 8),
              _StatRow(
                icon: Icons.inventory_2_outlined,
                texto:
                    '${camion.lineasCount} productos · ${camion.cajasTotalesObjetivo} cajas',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onIniciarPicking,
                  icon: const Icon(Icons.play_circle_outline_rounded, size: 24),
                  label: const Text('Iniciar picking'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.icon, required this.texto});

  final IconData icon;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.secondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texto,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

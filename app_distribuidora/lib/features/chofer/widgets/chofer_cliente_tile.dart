import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/chofer_cliente.dart';
import '../models/chofer_entrega_estado.dart';

class ChoferClienteTile extends StatelessWidget {
  const ChoferClienteTile({
    super.key,
    required this.cliente,
    required this.onIr,
    required this.onEntregado,
    required this.onIncidencia,
    required this.onAbrirDetalle,
  });

  final ChoferCliente cliente;
  final VoidCallback onIr;
  final VoidCallback onEntregado;
  final VoidCallback onIncidencia;
  final VoidCallback onAbrirDetalle;

  Color _bordeEstado() {
    return switch (cliente.estado) {
      ChoferEntregaEstado.pendiente => AppColors.estadoPendiente,
      ChoferEntregaEstado.entregado => AppColors.secondaryBlue,
      ChoferEntregaEstado.incidencia => AppColors.primaryRed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pend = cliente.esPendiente;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _bordeEstado(), width: 1.6),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onAbrirDetalle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cliente.nombreFantasia,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${cliente.ciudad} · ${cliente.direccion}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${cliente.distanciaMetrosMock} m · Orden ${cliente.ordenRuta}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    label: Text(
                      cliente.estado.label,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    side: BorderSide(color: _bordeEstado()),
                    backgroundColor: _bordeEstado().withValues(alpha: 0.12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: onIr,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Ir'),
                  ),
                  FilledButton(
                    onPressed: pend ? onEntregado : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.secondaryBlue,
                      foregroundColor: AppColors.onPrimaryWhite,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Entregado'),
                  ),
                  FilledButton(
                    onPressed: pend ? onIncidencia : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      foregroundColor: AppColors.onPrimaryWhite,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Incidencia'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

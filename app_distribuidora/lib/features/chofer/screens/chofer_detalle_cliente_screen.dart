import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/chofer_mock_repository.dart';
import '../models/chofer_cliente.dart';
import '../models/chofer_entrega_estado.dart';
import '../models/tipo_incidencia_chofer.dart';
import '../utils/chofer_launchers.dart';
import '../widgets/chofer_incidencia_sheet.dart';

class ChoferDetalleClienteScreen extends StatelessWidget {
  const ChoferDetalleClienteScreen({super.key, required this.clienteId});

  final String clienteId;

  void _whatsappSnack(BuildContext context, ChoferCliente c) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('${c.nombreFantasia} · ${c.estado.label}'),
        action: SnackBarAction(
          label: 'WhatsApp',
          onPressed: () {
            unawaited(
              launchWhatsAppReporteEntrega(
                telefono: c.telefono,
                nombreCliente: c.nombreFantasia,
                estadoLabel: c.estado.label,
                choferNombre: ChoferMockRepository.choferNombreDisplay,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ChoferMockRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final c = repo.byId(clienteId);
        if (c == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Cliente')),
            body: const Center(child: Text('Cliente no encontrado')),
          );
        }
        final dirCompleta = '${c.direccion}, ${c.ciudad}';
        return Scaffold(
          appBar: AppBar(title: Text(c.nombreFantasia)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Text(
                dirCompleta,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone_outlined),
                title: Text(c.telefono),
                trailing: TextButton(
                  onPressed: () => unawaited(launchTel(c.telefono)),
                  child: const Text('Llamar'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Vendedor asignado',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(c.vendedor, style: theme.textTheme.titleMedium),
              const SizedBox(height: 20),
              Text(
                'Documentos del día',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 8),
              ...c.documentosDia.map(
                (d) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(d)),
                    ],
                  ),
                ),
              ),
              if (c.incidenciaTipo != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Incidencia',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryRed,
                  ),
                ),
                Text(c.incidenciaTipo!.label),
                if (c.observacionIncidencia != null &&
                    c.observacionIncidencia!.trim().isNotEmpty)
                  Text(c.observacionIncidencia!),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: c.esPendiente
                          ? () {
                              repo.marcarEntregado(c.id);
                              _whatsappSnack(context, repo.byId(c.id)!);
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.secondaryBlue,
                        foregroundColor: AppColors.onPrimaryWhite,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Entregado'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: c.esPendiente
                          ? () {
                              showChoferIncidenciaSheet(
                                context,
                                onConfirmar: (tipo, obs, _) {
                                  repo.marcarIncidencia(
                                    c.id,
                                    tipo: tipo,
                                    observacion: obs,
                                  );
                                  _whatsappSnack(context, repo.byId(c.id)!);
                                },
                              );
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryRed,
                        foregroundColor: AppColors.onPrimaryWhite,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Incidencia'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

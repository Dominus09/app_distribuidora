import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/bodega_mock_repository.dart';
import '../models/picking_producto_mock.dart';
import 'picking_screen.dart';

/// Resumen de picking por camión (mock) + copiar faltantes.
class PickingResumenScreen extends StatelessWidget {
  const PickingResumenScreen({super.key, required this.camionId});

  final String camionId;

  String _textoFaltantes(List<PickingProductoMock> faltantes) {
    if (faltantes.isEmpty) {
      return 'Sin faltantes 🎉';
    }
    return faltantes
        .map(
          (p) =>
              '${p.nombreProducto} ${p.variante} → ${p.cajasFaltantes} caja(s) faltante(s)',
        )
        .join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = BodegaMockRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final c = repo.camion(camionId);
        final total = c.productos.length;
        final completos =
            c.productos.where((p) => p.cargaRealCajas >= p.cajasObjetivo).length;
        final incompletos = total - completos;
        final faltantes = repo.productosConFaltante(camionId);
        final textoCopiar = _textoFaltantes(faltantes);

        return Scaffold(
          appBar: AppBar(title: Text('Resumen · ${c.nombre}')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Text(
                'Totales',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              _ResumenRow(
                icon: Icons.check_circle_outline,
                color: Colors.green.shade700,
                titulo: 'Productos con carga completa',
                valor: '$completos / $total',
              ),
              const SizedBox(height: 10),
              _ResumenRow(
                icon: Icons.pending_actions,
                color: Colors.amber.shade900,
                titulo: 'Carga incompleta o pendiente',
                valor: '$incompletos',
              ),
              const SizedBox(height: 22),
              Text(
                'Detalle de faltantes (cajas)',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              if (faltantes.isEmpty)
                Text(
                  'No hay líneas con cajas faltantes.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...faltantes.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      tileColor: theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      title: Text(
                        p.nombreProducto,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${p.variante} → ${p.cajasFaltantes} caja(s) faltante(s)',
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: textoCopiar));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Faltantes copiados al portapapeles'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copiar faltantes'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Volver'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final idx = repo.indexCamion(camionId);
                        final lista = repo.camiones;
                        if (lista.isEmpty) return;
                        final next = lista[(idx + 1) % lista.length];
                        Navigator.of(context).pop();
                        Navigator.of(context).pop();
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => PickingScreen(camionId: next.id),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Siguiente camión'),
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

class _ResumenRow extends StatelessWidget {
  const _ResumenRow({
    required this.icon,
    required this.color,
    required this.titulo,
    required this.valor,
  });

  final IconData icon;
  final Color color;
  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: color, size: 32),
      title: Text(titulo, style: theme.textTheme.bodyLarge),
      trailing: Text(
        valor,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

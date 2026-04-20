import 'package:flutter/material.dart';

import '../models/picking_producto_mock.dart';

/// Tarjeta grande de línea de picking (validación + carga real).
class PickingProductoCard extends StatelessWidget {
  const PickingProductoCard({
    super.key,
    required this.producto,
    required this.onEscanearCodigo,
    required this.onIngresarCodigo,
    required this.onCambiarCargaCajas,
  });

  final PickingProductoMock producto;
  final VoidCallback onEscanearCodigo;
  final VoidCallback onIngresarCodigo;
  final ValueChanged<int> onCambiarCargaCajas;

  Color _bordeColor() {
    if (producto.hayErrorCodigo) return Colors.red.shade700;
    if (producto.pickingLineaCompleta) return Colors.green.shade700;
    if (producto.codigoValidado) return Colors.green.shade400;
    return Colors.amber.shade800;
  }

  Color _fondoSutil() {
    if (producto.hayErrorCodigo) return Colors.red.withValues(alpha: 0.06);
    if (producto.pickingLineaCompleta) return Colors.green.withValues(alpha: 0.08);
    if (producto.codigoValidado) return Colors.green.withValues(alpha: 0.05);
    return Colors.amber.withValues(alpha: 0.08);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = producto;
    return Card(
      elevation: 0,
      color: _fondoSutil(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _bordeColor(), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.nombreProducto,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              p.variante,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    'Tipo: ${p.tipoProducto}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                if (p.codigoValidado)
                  Chip(
                    avatar: Icon(Icons.verified_rounded, size: 18, color: Colors.green.shade800),
                    label: const Text('Validado'),
                    visualDensity: VisualDensity.compact,
                  ),
                if (p.hayErrorCodigo)
                  Chip(
                    avatar: Icon(Icons.error_outline, size: 18, color: Colors.red.shade800),
                    label: const Text('Código incorrecto'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MiniBlock(
                    titulo: 'Cajas a cargar',
                    valor: '${p.cajasObjetivo}',
                    destacado: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniBlock(
                    titulo: 'Unidades',
                    valor: '${p.unidadesObjetivo}',
                    destacado: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Cxc: ${p.cxc}',
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            SelectableText(
              'Código: ${p.codigoBarras}',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Carga real (cajas)',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: p.cargaRealCajas > 0
                      ? () => onCambiarCargaCajas(p.cargaRealCajas - 1)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${p.cargaRealCajas}',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => onCambiarCargaCajas(p.cargaRealCajas + 1),
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: 'Editar cantidad',
                  onPressed: () async {
                    final ctrl = TextEditingController(text: '${p.cargaRealCajas}');
                    try {
                      final r = await showDialog<int>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Carga real (cajas)'),
                          content: TextField(
                            controller: ctrl,
                            keyboardType: TextInputType.number,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Cajas',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancelar'),
                            ),
                            FilledButton(
                              onPressed: () {
                                Navigator.pop(ctx, int.tryParse(ctrl.text.trim()));
                              },
                              child: const Text('Aplicar'),
                            ),
                          ],
                        ),
                      );
                      if (r != null && context.mounted) {
                        onCambiarCargaCajas(r);
                      }
                    } finally {
                      ctrl.dispose();
                    }
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEscanearCodigo,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                    label: const Text('Escanear código'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onIngresarCodigo,
                    icon: const Icon(Icons.keyboard_outlined, size: 20),
                    label: const Text('Ingresar manual'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBlock extends StatelessWidget {
  const _MiniBlock({
    required this.titulo,
    required this.valor,
    required this.destacado,
  });

  final String titulo;
  final String valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: destacado
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              valor,
              style: (destacado ? theme.textTheme.headlineSmall : theme.textTheme.titleMedium)
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

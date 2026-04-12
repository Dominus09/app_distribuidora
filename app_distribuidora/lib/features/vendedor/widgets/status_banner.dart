import 'package:flutter/material.dart';

/// Aviso claro cuando no hay red: el vendedor puede seguir operando.
class OfflineWorkBanner extends StatelessWidget {
  const OfflineWorkBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: scheme.secondaryContainer.withValues(alpha: 0.85),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.wifi_off_rounded, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Estás sin conexión. Los registros se guardarán y se '
                'sincronizarán cuando vuelva internet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Franja compacta de conectividad (mock).
class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner({
    super.key,
    required this.isOnline,
    this.onToggleDemo,
  });

  final bool isOnline;
  final VoidCallback? onToggleDemo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isOnline
        ? const Color(0xFFE8F5E9)
        : scheme.errorContainer.withValues(alpha: 0.35);
    final fg = isOnline ? const Color(0xFF1B5E20) : scheme.onErrorContainer;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onToggleDemo,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                color: fg,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isOnline ? 'En línea' : 'Sin conexión',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (onToggleDemo != null)
                Text(
                  'Demo',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.8),
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel de estado de ruta del día (textos en español).
class RouteStatusPanel extends StatelessWidget {
  const RouteStatusPanel({
    super.key,
    required this.estadoLabel,
    required this.estadoColor,
    required this.progresoTexto,
    this.horaInicio,
    this.horaTermino,
  });

  final String estadoLabel;
  final Color estadoColor;
  final String progresoTexto;
  final String? horaInicio;
  final String? horaTermino;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estado de ruta',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: estadoColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    estadoLabel,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (horaInicio != null) ...[
              const SizedBox(height: 14),
              _rowIcon(
                context,
                Icons.play_circle_outline_rounded,
                'Hora inicio: $horaInicio',
              ),
            ],
            if (horaTermino != null) ...[
              const SizedBox(height: 8),
              _rowIcon(
                context,
                Icons.flag_circle_outlined,
                'Hora término: $horaTermino',
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'Progreso',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              progresoTexto,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowIcon(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

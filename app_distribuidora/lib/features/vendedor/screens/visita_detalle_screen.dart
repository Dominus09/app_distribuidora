import 'package:flutter/material.dart';

import '../models/visita.dart';
import '../models/visita_estado.dart';

class VisitaDetalleScreen extends StatefulWidget {
  const VisitaDetalleScreen({super.key, required this.visita});

  final Visita visita;

  @override
  State<VisitaDetalleScreen> createState() => _VisitaDetalleScreenState();
}

class _VisitaDetalleScreenState extends State<VisitaDetalleScreen> {
  late VisitaEstado _estado;
  late final TextEditingController _observacionesController;

  @override
  void initState() {
    super.initState();
    _estado = widget.visita.estado;
    _observacionesController = TextEditingController(
      text: widget.visita.observaciones,
    );
  }

  @override
  void dispose() {
    _observacionesController.dispose();
    super.dispose();
  }

  void _guardar() {
    final result = widget.visita.copyWith(
      estado: _estado,
      observaciones: _observacionesController.text.trim(),
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = widget.visita;
    final c = _estado.indicatorColor;

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de visita')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.cliente,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.place_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          v.direccion,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _estado.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: c,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => setState(() => _estado = VisitaEstado.visitado),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Marcar como visitado'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => setState(() => _estado = VisitaEstado.incidencia),
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('Marcar incidencia'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              foregroundColor: const Color(0xFFB71C1C),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Observaciones',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _observacionesController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Notas de la visita…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _guardar,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

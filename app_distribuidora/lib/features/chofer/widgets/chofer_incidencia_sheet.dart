import 'package:flutter/material.dart';

import '../models/tipo_incidencia_chofer.dart';

/// Bottom sheet mock: tipo + observación + evidencia simulada.
Future<void> showChoferIncidenciaSheet(
  BuildContext context, {
  required void Function(TipoIncidenciaChofer tipo, String? observacion, bool evidenciaSimulada)
      onConfirmar,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return _IncidenciaBody(onConfirmar: onConfirmar);
    },
  );
}

class _IncidenciaBody extends StatefulWidget {
  const _IncidenciaBody({required this.onConfirmar});

  final void Function(TipoIncidenciaChofer tipo, String? observacion, bool evidenciaSimulada)
      onConfirmar;

  @override
  State<_IncidenciaBody> createState() => _IncidenciaBodyState();
}

class _IncidenciaBodyState extends State<_IncidenciaBody> {
  TipoIncidenciaChofer _tipo = TipoIncidenciaChofer.clienteCerrado;
  final _obsCtrl = TextEditingController();
  bool _evidenciaSim = false;

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Registrar incidencia',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          Text(
            'Tipo de incidencia',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in TipoIncidenciaChofer.values)
                ChoiceChip(
                  label: Text(t.label),
                  selected: _tipo == t,
                  onSelected: (_) => setState(() => _tipo = t),
                ),
            ],
          ),
          TextField(
            controller: _obsCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observación (opcional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Evidencia (simulada)'),
            subtitle: const Text('Marca como si hubieras adjuntado foto'),
            value: _evidenciaSim,
            onChanged: (v) => setState(() => _evidenciaSim = v ?? false),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              widget.onConfirmar(
                _tipo,
                _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
                _evidenciaSim,
              );
              Navigator.of(context).pop();
            },
            child: const Text('Guardar incidencia'),
          ),
        ],
      ),
    );
  }
}

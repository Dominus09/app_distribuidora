import 'package:flutter/material.dart';

/// Filtros de búsqueda, tipo, estado y orden de pendientes.
class PickingFiltersBar extends StatelessWidget {
  const PickingFiltersBar({
    super.key,
    required this.busquedaController,
    required this.onBusquedaChanged,
    required this.tipoSeleccionado,
    required this.onTipoChanged,
    required this.estadoFiltro,
    required this.onEstadoFiltroChanged,
    required this.ordenPendientesPorTipo,
    required this.onOrdenPendientesChanged,
  });

  final TextEditingController busquedaController;
  final ValueChanged<String> onBusquedaChanged;
  final String tipoSeleccionado;
  final ValueChanged<String> onTipoChanged;
  final FiltroEstadoPicking estadoFiltro;
  final ValueChanged<FiltroEstadoPicking> onEstadoFiltroChanged;
  final bool ordenPendientesPorTipo;
  final ValueChanged<bool> onOrdenPendientesChanged;

  static const tiposProducto = <String>[
    'Todos',
    'Bebidas',
    'Abarrotes',
    'Lácteos',
    'Congelados',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: busquedaController,
          onChanged: onBusquedaChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar por producto o variante…',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Tipo de producto',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in tiposProducto)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(t),
                    selected: tipoSeleccionado == t,
                    onSelected: (_) => onTipoChanged(t),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Estado',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        SegmentedButton<FiltroEstadoPicking>(
          segments: const [
            ButtonSegment(value: FiltroEstadoPicking.todos, label: Text('Todos')),
            ButtonSegment(value: FiltroEstadoPicking.pendientes, label: Text('Pendientes')),
            ButtonSegment(value: FiltroEstadoPicking.validados, label: Text('Validados')),
            ButtonSegment(value: FiltroEstadoPicking.conError, label: Text('Con error')),
          ],
          selected: {estadoFiltro},
          onSelectionChanged: (s) => onEstadoFiltroChanged(s.first),
        ),
        const SizedBox(height: 10),
        Text(
          'Orden pendientes',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Por tipo')),
            ButtonSegment(value: false, label: Text('Por nombre')),
          ],
          selected: {ordenPendientesPorTipo},
          onSelectionChanged: (s) => onOrdenPendientesChanged(s.first),
        ),
      ],
    );
  }
}

enum FiltroEstadoPicking {
  todos,
  pendientes,
  validados,
  conError,
}

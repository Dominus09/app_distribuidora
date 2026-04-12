import 'package:flutter/material.dart';

import '../models/visita.dart';
import '../models/visita_estado.dart';
import '../widgets/visita_ruta_card.dart';
import 'visita_detalle_screen.dart';

class RutaScreen extends StatefulWidget {
  const RutaScreen({
    super.key,
    required this.visitas,
    required this.onVisitasChanged,
  });

  final List<Visita> visitas;
  final ValueChanged<List<Visita>> onVisitasChanged;

  @override
  State<RutaScreen> createState() => _RutaScreenState();
}

class _RutaScreenState extends State<RutaScreen> {
  late List<Visita> _visitas;

  @override
  void initState() {
    super.initState();
    _visitas = List<Visita>.from(widget.visitas);
  }

  void _emit(List<Visita> next) {
    setState(() => _visitas = next);
    widget.onVisitasChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ruta del día')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _visitas.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warehouse_outlined,
                        size: 32,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Base de salida',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final i = index - 1;
          final visita = _visitas[i];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: VisitaRutaCard(
              visita: visita,
              onVisited: () {
                final next = [..._visitas];
                next[i] = visita.copyWith(estado: VisitaEstado.visitado);
                _emit(next);
              },
              onIncidencia: () {
                final next = [..._visitas];
                next[i] = visita.copyWith(estado: VisitaEstado.incidencia);
                _emit(next);
              },
              onTap: () async {
                final updated = await Navigator.of(context).push<Visita>(
                  MaterialPageRoute<Visita>(
                    builder: (_) => VisitaDetalleScreen(visita: visita),
                  ),
                );
                if (updated != null && context.mounted) {
                  final next = [..._visitas];
                  next[i] = updated;
                  _emit(next);
                }
              },
            ),
          );
        },
      ),
    );
  }
}

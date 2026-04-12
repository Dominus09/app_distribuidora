import 'package:flutter/material.dart';

import '../models/visita.dart';
import '../models/visita_estado.dart';
import '../services/mock_visitas.dart';
import '../utils/vendedor_date_labels.dart';
import '../widgets/clientes_map_placeholder.dart';
import '../widgets/dashboard_summary_card.dart';
import '../widgets/route_status_card.dart';
import 'ruta_screen.dart';

class VendedorHomeScreen extends StatefulWidget {
  const VendedorHomeScreen({
    super.key,
    this.vendedorNombre = 'Juan',
  });

  final String vendedorNombre;

  @override
  State<VendedorHomeScreen> createState() => _VendedorHomeScreenState();
}

class _VendedorHomeScreenState extends State<VendedorHomeScreen> {
  bool _routeStarted = false;
  bool _routeFinished = false;
  DateTime? _startTime;
  late List<Visita> _visitas;

  @override
  void initState() {
    super.initState();
    _visitas = List<Visita>.from(mockVisitasDelDia());
  }

  int get _totalClientes => _visitas.length;

  int get _visitados =>
      _visitas.where((v) => v.estado == VisitaEstado.visitado).length;

  int get _pendientes =>
      _visitas.where((v) => v.estado == VisitaEstado.pendiente).length;

  String get _estadoRutaLabel {
    if (_routeFinished) return 'Finalizada';
    if (_routeStarted) return 'En progreso';
    return 'No iniciada';
  }

  Color get _estadoRutaColor {
    if (_routeFinished) return const Color(0xFF2E7D32);
    if (_routeStarted) return const Color(0xFF1565C0);
    return const Color(0xFF757575);
  }

  String get _progresoTexto => '$_visitados de $_totalClientes clientes';

  void _iniciarRuta() {
    setState(() {
      _routeStarted = true;
      _routeFinished = false;
      _startTime = DateTime.now();
    });
  }

  void _finalizarRuta() {
    setState(() {
      _routeFinished = true;
    });
  }

  void _abrirRuta() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RutaScreen(
          visitas: _visitas,
          onVisitasChanged: (next) {
            setState(() => _visitas = next);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Inicio')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
            const SizedBox(height: 8),
            Text(
              'Bienvenido, ${widget.vendedorNombre}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Hoy: ${diaSemanaHoy()}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            RouteStatusCard(
              estadoLabel: _estadoRutaLabel,
              estadoColor: _estadoRutaColor,
              horaInicio: _routeStarted && _startTime != null
                  ? horaCorta(_startTime!)
                  : null,
              progresoTexto: _progresoTexto,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DashboardSummaryCard(
                    title: 'Pendientes',
                    value: '$_pendientes',
                    icon: Icons.pending_actions_outlined,
                    color: const Color(0xFFF9A825),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DashboardSummaryCard(
                    title: 'Visitados',
                    value: '$_visitados',
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const ClientesMapPlaceholder(),
            const SizedBox(height: 24),
            if (!_routeStarted && !_routeFinished) ...[
              FilledButton.icon(
                onPressed: _iniciarRuta,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Iniciar Ruta'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                ),
              ),
            ] else if (_routeStarted && !_routeFinished) ...[
              FilledButton.icon(
                onPressed: _abrirRuta,
                icon: const Icon(Icons.route_rounded),
                label: const Text('Ver Ruta'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _finalizarRuta,
                icon: const Icon(Icons.flag_rounded),
                label: const Text('Finalizar Ruta'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                ),
              ),
            ] else ...[
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Icon(
                        Icons.task_alt_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ruta finalizada. Puedes revisar el progreso arriba.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
      ),
    );
  }
}

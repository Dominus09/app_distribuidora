import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../auth/auth_navigation.dart';
import '../../auth/services/auth_service.dart';
import '../models/visita.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../services/vendedor_service.dart';
import '../widgets/status_banner.dart';
import '../widgets/summary_card.dart';
import 'ruta_screen.dart';

/// Dashboard principal del vendedor (ruta desde API + caché local).
class VendedorHomeScreen extends StatefulWidget {
  const VendedorHomeScreen({
    super.key,
    this.vendedorCodigo = 'vendedor_1',
    this.vendedorNombre = 'Vendedor',
    this.vendedorService,
    this.syncService,
    this.locationService,
    this.apiService,
    this.authService,
  });

  /// Código para query `GET .../vendedor/ruta?vendedor=`.
  final String vendedorCodigo;
  /// Nombre para saludo en UI.
  final String vendedorNombre;
  final VendedorService? vendedorService;
  final SyncService? syncService;
  final LocationService? locationService;
  final ApiService? apiService;
  final DistribuidoraAuthService? authService;

  @override
  State<VendedorHomeScreen> createState() => _VendedorHomeScreenState();
}

class _VendedorHomeScreenState extends State<VendedorHomeScreen> {
  late final VendedorService _vendedorService;
  late final SyncService _syncService;
  late final LocationService _locationService;
  late final ApiService _apiService;
  late final DistribuidoraAuthService _authService;

  late Future<List<Visita>> _rutaFuture;

  bool _routeStarted = false;
  bool _routeFinished = false;
  DateTime? _startTime;
  DateTime? _endTime;
  /// Simula falta de red (pruebas); la API solo se intenta si también hay conectividad real.
  bool _forceOffline = false;
  bool _connectivityOk = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool get _attemptRemoteSave => _connectivityOk && !_forceOffline;

  bool _syncBusy = false;
  List<Visita> _visitas = [];

  /// Tras confirmar el cierre: cumplimiento y conteos (persistencia mock en estado).
  double? _porcentajeCumplimiento;
  String? _estadoRutaCierre;
  int? _clientesVisitadosCierre;
  int? _clientesPendientesCierre;

  @override
  void initState() {
    super.initState();
    _vendedorService = widget.vendedorService ?? VendedorService();
    _syncService = widget.syncService ?? SyncService();
    _locationService = widget.locationService ?? LocationService();
    _apiService = widget.apiService ?? ApiService();
    _authService = widget.authService ?? DistribuidoraAuthService();
    _rutaFuture = _cargarRutaDesdeApi();
    _rutaFuture.then((list) {
      if (mounted) setState(() => _visitas = list);
    });
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final ok = results.any((r) => r != ConnectivityResult.none);
      if (mounted) setState(() => _connectivityOk = ok);
    });
    Connectivity().checkConnectivity().then((results) {
      final ok = results.any((r) => r != ConnectivityResult.none);
      if (mounted) setState(() => _connectivityOk = ok);
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// Carga remota con respaldo en disco si falla la API.
  Future<List<Visita>> _cargarRutaDesdeApi() async {
    final fecha = _fechaApi(DateTime.now());
    try {
      final list =
          await _apiService.getRutaDelDia(fecha, widget.vendedorCodigo);
      await _vendedorService.persistVisitasToDisk(list);
      return list;
    } catch (_) {
      final cached = await _vendedorService.loadVisitasFromDisk();
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  void _programarRecargaRuta() {
    setState(() {
      _rutaFuture = _cargarRutaDesdeApi();
    });
    _rutaFuture.then((list) {
      if (mounted) setState(() => _visitas = list);
    });
  }

  Future<void> _cerrarSesion() async {
    await _authService.logout();
    if (!context.mounted) return;
    replaceWithDistribuidoraLogin(context);
  }

  static String _fechaApi(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  int get _totalClientes => _visitas.length;

  int get _visitados =>
      _visitas.where((v) => v.estado == VisitaEstado.visitado).length;

  int get _pendientes =>
      _visitas.where((v) => v.estado == VisitaEstado.pendiente).length;

  int get _incidencias =>
      _visitas.where((v) => v.estado == VisitaEstado.incidencia).length;

  int get _pendientesSync =>
      _visitas.where((v) => v.syncStatus == SyncStatus.pendingSync).length;

  String get _estadoRutaLabel {
    if (_routeFinished) {
      if (_estadoRutaCierre == 'completada') return 'Finalizada (completada)';
      if (_estadoRutaCierre == 'incompleta') return 'Finalizada (incompleta)';
      return 'Finalizada';
    }
    if (_routeStarted) return 'En progreso';
    return 'No iniciada';
  }

  Color get _estadoRutaColor {
    if (_routeFinished) {
      if (_estadoRutaCierre == 'completada') return const Color(0xFF2E7D32);
      if (_estadoRutaCierre == 'incompleta') return const Color(0xFFE65100);
      return const Color(0xFF546E7A);
    }
    if (_routeStarted) return const Color(0xFF1565C0);
    return const Color(0xFF757575);
  }

  /// Paradas con resultado (visitado o incidencia), coherente con el cierre de ruta.
  int get _clientesAtendidos =>
      _totalClientes -
      _visitas.where((v) => v.estado == VisitaEstado.pendiente).length;

  String get _progresoTexto =>
      '$_clientesAtendidos de $_totalClientes clientes';

  void _setVisitas(List<Visita> next) {
    setState(() {
      _visitas = next;
      _rutaFuture = Future<List<Visita>>.value(next);
    });
    unawaited(_vendedorService.persistVisitasToDisk(next));
  }

  void _iniciarRuta() {
    setState(() {
      _routeStarted = true;
      _routeFinished = false;
      _startTime = DateTime.now();
      _endTime = null;
      _porcentajeCumplimiento = null;
      _estadoRutaCierre = null;
      _clientesVisitadosCierre = null;
      _clientesPendientesCierre = null;
    });
  }

  /// Progreso operativo: visitados = con resultado (visitado o incidencia); pendientes = aún pendiente.
  _ProgresoRuta _calcularProgreso() {
    final total = _totalClientes;
    final pendientes = _pendientes;
    final visitados = _clientesAtendidos;
    final pct = total == 0 ? 0.0 : (visitados / total) * 100;
    final estado = visitados == total ? 'completada' : 'incompleta';
    return _ProgresoRuta(
      totalClientes: total,
      clientesVisitados: visitados,
      clientesPendientes: pendientes,
      porcentajeCumplimiento: pct,
      estadoRuta: estado,
    );
  }

  /// Muestra confirmación y, si aplica, cierra la ruta con métricas.
  Future<void> _solicitarFinalizarRuta() async {
    final p = _calcularProgreso();
    final sinPendientes = p.clientesPendientes == 0;

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Finalizar ruta'),
          content: sinPendientes
              ? const Text(
                  'Has completado todos los clientes.\n\n'
                  '¿Deseas finalizar la ruta?',
                )
              : Text(
                  '¿Deseas finalizar la ruta?\n\n'
                  'Has completado ${p.clientesVisitados} de ${p.totalClientes} clientes.\n'
                  'Te faltan ${p.clientesPendientes} cliente(s) por visitar.',
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              child: const Text('Finalizar Ruta'),
            ),
          ],
        );
      },
    );

    if (confirmar == true && mounted) {
      _finalizarRuta(p);
    }
  }

  /// Aplica cierre confirmado: estado de ruta, hora fin y resumen de cumplimiento.
  void _finalizarRuta(_ProgresoRuta p) {
    final pctRedondeado = double.parse(p.porcentajeCumplimiento.toStringAsFixed(1));

    setState(() {
      _routeFinished = true;
      _routeStarted = false;
      _endTime = DateTime.now();
      _porcentajeCumplimiento = pctRedondeado;
      _estadoRutaCierre = p.estadoRuta;
      _clientesVisitadosCierre = p.clientesVisitados;
      _clientesPendientesCierre = p.clientesPendientes;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Ruta finalizada · Cumplimiento: ${pctRedondeado.toStringAsFixed(1)}%',
        ),
      ),
    );
  }

  void _abrirRuta() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RutaScreen(
          visitas: _visitas,
          attemptRemoteSave: _attemptRemoteSave,
          locationService: _locationService,
          vendedorService: _vendedorService,
          syncService: _syncService,
          apiService: _apiService,
          onVisitasChanged: _setVisitas,
          reloadRuta: _cargarRutaDesdeApi,
        ),
      ),
    );
  }

  Future<void> _sincronizacionForzada() async {
    if (_syncBusy) return;
    setState(() => _syncBusy = true);
    final r = await _syncService.forceSyncPending(_visitas, _apiService);
    if (!mounted) return;
    setState(() {
      _visitas = r.visitas;
      _rutaFuture = Future<List<Visita>>.value(r.visitas);
      _syncBusy = false;
    });
    unawaited(_vendedorService.persistVisitasToDisk(r.visitas));

    final mensaje = r.errorMessage != null
        ? 'Error al sincronizar: ${r.errorMessage}'
        : r.duplicateRun
            ? 'Ya hay una sincronización en curso. Espera un momento e inténtalo de nuevo.'
            : '${r.newlySyncedCount} registro(s) sincronizado(s).\n'
                '${r.skippedDuplicatesCount} omitido(s) (duplicado o ya enviado).\n'
                '${r.stillPendingCount} pendiente(s) de envío.';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sincronización completada'),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ahora = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: [
          TextButton(
            onPressed: _cerrarSesion,
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
      body: FutureBuilder<List<Visita>>(
        future: _rutaFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _visitas.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && _visitas.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'No se pudo cargar la ruta',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _programarRecargaRuta,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              _programarRecargaRuta();
              await _rutaFuture;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
          const SizedBox(height: 4),
          Text(
            'Bienvenido, ${widget.vendedorNombre}',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Fecha: ${_fechaCorta(ahora)}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Día de atención: ${_diaSemana(ahora)}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ConnectionStatusBanner(
            isOnline: _attemptRemoteSave,
            onToggleDemo: () => setState(() => _forceOffline = !_forceOffline),
          ),
          if (!_attemptRemoteSave) ...[
            const SizedBox(height: 12),
            const OfflineWorkBanner(),
          ],
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: SwitchListTile(
              title: const Text('GPS simulado disponible'),
              subtitle: const Text(
                'Desactívalo para probar visitas sin señal de ubicación.',
              ),
              value: _locationService.mockGpsAvailable,
              onChanged: (v) => setState(() => _locationService.mockGpsAvailable = v),
            ),
          ),
          const SizedBox(height: 16),
          RouteStatusPanel(
            estadoLabel: _estadoRutaLabel,
            estadoColor: _estadoRutaColor,
            progresoTexto: _progresoTexto,
            horaInicio: _startTime != null && (_routeStarted || _routeFinished)
                ? _hora(_startTime!)
                : null,
            horaTermino:
                _routeFinished && _endTime != null ? _hora(_endTime!) : null,
          ),
          const SizedBox(height: 16),
          SummaryCard(
            title: 'Pendientes',
            value: '$_pendientes',
            icon: Icons.pending_actions_outlined,
            accentColor: const Color(0xFF2E7D32),
          ),
          const SizedBox(height: 10),
          SummaryCard(
            title: 'Visitados',
            value: '$_visitados',
            icon: Icons.check_circle_outline,
            accentColor: const Color(0xFF1565C0),
          ),
          const SizedBox(height: 10),
          SummaryCard(
            title: 'Incidencias',
            value: '$_incidencias',
            icon: Icons.warning_amber_rounded,
            accentColor: const Color(0xFFC62828),
          ),
          const SizedBox(height: 18),
          Text(
            'Pendientes de envío al servidor: $_pendientesSync',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: _syncBusy ? null : _sincronizacionForzada,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
            ),
            child: _syncBusy
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text('Sincronizando…'),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.sync_rounded),
                      SizedBox(width: 10),
                      Text('Sincronización forzada'),
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.65,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              height: 168,
              width: double.infinity,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.map_outlined,
                      size: 42,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Mapa en "Ver Ruta"',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Clientes, GPS simulado y navegación',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
            FilledButton.icon(
              onPressed: _solicitarFinalizarRuta,
              icon: const Icon(Icons.flag_rounded),
              label: const Text('Finalizar Ruta'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
            ),
          ] else ...[
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ruta finalizada. Revisa el resumen y la hora de término arriba.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_porcentajeCumplimiento != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Cumplimiento: ${_porcentajeCumplimiento!.toStringAsFixed(1)}%',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            if (_clientesVisitadosCierre != null &&
                                _clientesPendientesCierre != null)
                              Text(
                                'Atendidos: $_clientesVisitadosCierre · '
                                'Pendientes al cierre: $_clientesPendientesCierre',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ],
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
        },
      ),
    );
  }

  static String _fechaCorta(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd-$mm-${d.year}';
  }

  static String _diaSemana(DateTime d) {
    const nombres = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    return nombres[d.weekday - 1];
  }

  static String _hora(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Resumen numérico al cerrar la ruta (sin API).
class _ProgresoRuta {
  const _ProgresoRuta({
    required this.totalClientes,
    required this.clientesVisitados,
    required this.clientesPendientes,
    required this.porcentajeCumplimiento,
    required this.estadoRuta,
  });

  final int totalClientes;
  final int clientesVisitados;
  final int clientesPendientes;
  final double porcentajeCumplimiento;

  /// `completada` si no quedaban paradas pendientes; si no, `incompleta`.
  final String estadoRuta;
}

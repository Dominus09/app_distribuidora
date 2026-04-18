import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/auth_navigation.dart';
import '../../auth/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../models/visita.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../services/vendedor_service.dart';
import '../widgets/terreno_sync_banner.dart';
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
  /// Simula falta de red (pruebas); la API solo se intenta si también hay conectividad real.
  bool _forceOffline = false;
  bool _connectivityOk = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool get _attemptRemoteSave => _connectivityOk && !_forceOffline;

  /// Wi‑Fi, datos móviles, ethernet, VPN o satélite (no solo `none` / bluetooth).
  static bool _hayRedDatos(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    const conDatos = <ConnectivityResult>{
      ConnectivityResult.wifi,
      ConnectivityResult.mobile,
      ConnectivityResult.ethernet,
      ConnectivityResult.vpn,
      ConnectivityResult.other,
      ConnectivityResult.satellite,
    };
    return results.any(conDatos.contains);
  }

  bool _syncBusy = false;
  List<Visita> _visitas = [];

  /// Tras confirmar el cierre: cumplimiento y conteos (persistencia mock en estado).
  double? _porcentajeCumplimiento;
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
      final previousOk = _connectivityOk;
      final ok = _hayRedDatos(results);
      if (!mounted) return;
      setState(() => _connectivityOk = ok);
      if (!context.mounted) return;
      if (ok && !previousOk && !_forceOffline) {
        final hay = _visitas.any(
          (v) =>
              v.syncStatus == SyncStatus.pendingSync ||
              v.syncStatus == SyncStatus.syncError,
        );
        if (hay) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hay registros pendientes por sincronizar'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });
    Connectivity().checkConnectivity().then((results) {
      final ok = _hayRedDatos(results);
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
    if (!mounted) return;
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

  int get _pendientes =>
      _visitas.where((v) => v.estado == VisitaEstado.pendiente).length;

  int get _visitados =>
      _visitas.where((v) => v.estado == VisitaEstado.visitado).length;

  int get _incidencias =>
      _visitas.where((v) => v.estado == VisitaEstado.incidencia).length;

  /// Paradas ya registradas (visitado o incidencia); coherente con barra y cierre de ruta.
  int get _clientesAtendidos =>
      _totalClientes -
      _visitas.where((v) => v.estado == VisitaEstado.pendiente).length;

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
      _porcentajeCumplimiento = null;
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
    return _ProgresoRuta(
      totalClientes: total,
      clientesVisitados: visitados,
      clientesPendientes: pendientes,
      porcentajeCumplimiento: pct,
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
                backgroundColor: AppColors.primaryRed,
                foregroundColor: AppColors.onPrimaryWhite,
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
      _porcentajeCumplimiento = pctRedondeado;
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

  static final Uri _urlCatalogo = Uri.parse('https://cat.quillotana.cl');
  static final Uri _urlBsale =
      Uri.parse('https://app.bsale.cl/documents/sales');

  static String _barraProgresoAscii(int hechos, int total) {
    if (total <= 0) return '░' * 10;
    const segmentos = 10;
    final llenos = ((hechos * segmentos) / total).floor().clamp(0, segmentos);
    return '${'█' * llenos}${'░' * (segmentos - llenos)}';
  }

  Future<void> _abrirEnlaceExterno(Uri uri, String etiquetaError) async {
    try {
      final ok = await canLaunchUrl(uri);
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se puede abrir $etiquetaError'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al abrir $etiquetaError'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _sincronizacionForzada() async {
    if (_syncBusy) return;
    if (!_connectivityOk || _forceOffline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay conexión disponible'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _syncBusy = true);
    try {
      final alcanzable = await _apiService.pingReachable();
      if (!mounted) return;
      if (!alcanzable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay conexión disponible'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final r = await _syncService.forceSyncPending(_visitas, _apiService);
      if (!mounted) return;
      setState(() {
        _visitas = r.visitas;
        _rutaFuture = Future<List<Visita>>.value(r.visitas);
      });
      unawaited(_vendedorService.persistVisitasToDisk(r.visitas));

      final String mensaje;
      if (r.duplicateRun) {
        mensaje =
            'Ya hay una sincronización en curso. Espera un momento e inténtalo de nuevo.';
      } else if (r.blockedMessage != null &&
          r.syncedCount == 0 &&
          r.omittedCount == 0 &&
          r.errorCount == 0) {
        mensaje = r.blockedMessage!;
      } else {
        final lineas = <String>[
          '${r.syncedCount} registro(s) sincronizado(s).',
          '${r.omittedCount} omitido(s).',
          '${r.errorCount} con error.',
        ];
        if (r.pendingAfterCount > 0 || r.syncErrorAfterCount > 0) {
          lineas.add(
            'En cola: ${r.pendingAfterCount} pendiente(s), '
            '${r.syncErrorAfterCount} con error de sincronización.',
          );
        }
        if (r.blockedMessage != null) {
          lineas.add(r.blockedMessage!);
        }
        mensaje = lineas.join('\n');
      }

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
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ahora = DateTime.now();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        leadingWidth: 52,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.asset(
            'assets/images/logo_small.png',
            height: 30,
            fit: BoxFit.contain,
          ),
        ),
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
          late final Widget bodyContent;
          if (snapshot.connectionState == ConnectionState.waiting &&
              _visitas.isEmpty) {
            bodyContent = const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError && _visitas.isEmpty) {
            bodyContent = Center(
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
          } else {
            bodyContent = RefreshIndicator(
            onRefresh: () async {
              _programarRecargaRuta();
              await _rutaFuture;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'Hola, ${widget.vendedorNombre}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _fechaLarga(ahora),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fechaCorta(ahora),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Día de atención: ${_diaSemana(ahora)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Resumen del día',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ResumenDiaTile(
                        valor: '$_pendientes',
                        etiqueta: 'Pendientes',
                        color: AppColors.estadoPendiente,
                        icon: Icons.pending_actions_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ResumenDiaTile(
                        valor: '$_visitados',
                        etiqueta: 'Visitados',
                        color: AppColors.secondaryBlue,
                        icon: Icons.check_circle_outline,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ResumenDiaTile(
                        valor: '$_incidencias',
                        etiqueta: 'Incidencias',
                        color: AppColors.primaryRed,
                        icon: Icons.warning_amber_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  'Progreso',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 10),
                if (_totalClientes > 0) ...[
                  Text(
                    '[ ${_barraProgresoAscii(_clientesAtendidos, _totalClientes)} ]  $_clientesAtendidos / $_totalClientes',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      minHeight: 12,
                      value: _clientesAtendidos / _totalClientes,
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Registrados en ruta (visitas e incidencias) frente al total del día.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ] else
                  Text(
                    'Sin clientes cargados para hoy.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 32),
                Text(
                  'Acciones',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 12),
                if (!_routeStarted && !_routeFinished) ...[
                  FilledButton.icon(
                    onPressed: _iniciarRuta,
                    icon: const Icon(Icons.play_arrow_rounded, size: 26),
                    label: const Text('Iniciar ruta'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ] else if (_routeStarted && !_routeFinished) ...[
                  FilledButton.icon(
                    onPressed: _abrirRuta,
                    icon: const Icon(Icons.route_rounded, size: 26),
                    label: const Text('Ver ruta'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _solicitarFinalizarRuta,
                    icon: const Icon(Icons.flag_rounded),
                    label: const Text('Finalizar ruta'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      foregroundColor: AppColors.primaryRed,
                      side: const BorderSide(color: AppColors.primaryRed, width: 1.5),
                      backgroundColor: AppColors.surface,
                    ),
                  ),
                ] else ...[
                  Card(
                    elevation: 2,
                    color: AppColors.surface,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: AppColors.secondaryBlue.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: AppColors.secondaryBlue.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Icon(
                            Icons.task_alt_rounded,
                            color: theme.colorScheme.primary,
                            size: 36,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ruta finalizada',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (_porcentajeCumplimiento != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Cumplimiento: ${_porcentajeCumplimiento!.toStringAsFixed(1)}%',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  if (_clientesVisitadosCierre != null &&
                                      _clientesPendientesCierre != null)
                                    Text(
                                      'Al cierre: $_clientesVisitadosCierre atendidos · '
                                      '$_clientesPendientesCierre pendientes',
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
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _abrirRuta,
                    icon: const Icon(Icons.route_rounded, size: 26),
                    label: const Text('Ver ruta'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _syncBusy ? null : _sincronizacionForzada,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    backgroundColor: theme.colorScheme.secondary,
                    foregroundColor: theme.colorScheme.onSecondary,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_syncBusy)
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onSecondary,
                          ),
                        )
                      else
                        Icon(
                          Icons.sync_rounded,
                          size: 26,
                          color: theme.colorScheme.onSecondary,
                        ),
                      const SizedBox(width: 10),
                      Text(
                        _syncBusy
                            ? 'Sincronizando…'
                            : 'Sincronización forzada',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  'Herramientas',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      _abrirEnlaceExterno(_urlCatalogo, 'el catálogo'),
                  icon: const Icon(Icons.menu_book_outlined, size: 24),
                  label: const Text('Ver Catálogo'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _abrirEnlaceExterno(_urlBsale, 'Bsale'),
                  icon: const Icon(Icons.receipt_long_outlined, size: 24),
                  label: const Text('Ir a Bsale'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TerrenoSyncBanner(
                interfaceConnected: _attemptRemoteSave,
                anyItemSyncing: _visitas.any(
                  (v) => v.syncStatus == SyncStatus.syncing,
                ),
                batchSyncing: _syncBusy,
              ),
              Expanded(child: bodyContent),
            ],
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

  static String _fechaLarga(DateTime d) {
    const meses = <String>[
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${d.day} de ${meses[d.month - 1]} de ${d.year}';
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
}

class _ResumenDiaTile extends StatelessWidget {
  const _ResumenDiaTile({
    required this.valor,
    required this.etiqueta,
    required this.color,
    required this.icon,
  });

  final String valor;
  final String etiqueta;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface,
      elevation: 1,
      shadowColor: AppColors.secondaryBlue.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                valor,
                maxLines: 1,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              etiqueta,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resumen numérico al cerrar la ruta (sin API).
class _ProgresoRuta {
  const _ProgresoRuta({
    required this.totalClientes,
    required this.clientesVisitados,
    required this.clientesPendientes,
    required this.porcentajeCumplimiento,
  });

  final int totalClientes;
  final int clientesVisitados;
  final int clientesPendientes;
  final double porcentajeCumplimiento;
}

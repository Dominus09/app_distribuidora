import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/auth_navigation.dart';
import '../../auth/services/auth_service.dart';
import '../../../core/session/operational_scope.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/sync/crash_recovery_service.dart';
import '../../../core/sync/write_ahead_visit_sync.dart';
import '../../../core/telemetry/operational_status_snapshot.dart';
import '../../../core/telemetry/operational_telemetry_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/field_log.dart';
import '../models/visita.dart';
import '../services/api_service.dart';
import '../services/georef_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../services/vendedor_service.dart';
import '../../../core/telemetry/telemetry_config.dart';
import '../widgets/operational_status_listener.dart';
import '../widgets/ruta_activa_card.dart';
import '../widgets/ruta_progreso_card.dart';
import '../widgets/terreno_enlace_chip.dart';
import '../services/georef_local_store.dart';
import '../../../core/telemetry/outbox_observability.dart';
import '../../../core/telemetry/timer_registry.dart';
import 'georef_pendientes_screen.dart';
import 'outbox_debug_screen.dart';
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

class _VendedorHomeScreenState extends State<VendedorHomeScreen>
    with WidgetsBindingObserver {
  late final VendedorService _vendedorService;
  late final SyncService _syncService;
  late final LocationService _locationService;
  late final ApiService _apiService;
  late final DistribuidoraAuthService _authService;
  late final OperationalTelemetryService _telemetry;
  late final GeorefService _georefService;

  late Future<List<Visita>> _rutaFuture;

  bool _routeStarted = false;
  bool _routeFinished = false;
  /// Simula falta de red (pruebas); la API solo se intenta si también hay conectividad real.
  final bool _forceOffline = false;
  bool _connectivityOk = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _apiReachProbeTimer;
  DateTime? _apiOkBypassUntil;
  Timer? _resumeDebounce;
  Timer? _operacionalRefreshTimer;
  Timer? _outboxBackgroundFlushTimer;
  Timer? _operacionalDebounce;
  final ValueNotifier<OperationalStatusSnapshot?> _operacionalNotifier =
      ValueNotifier<OperationalStatusSnapshot?>(null);

  /// Incluye bypass si el servidor responde aunque `connectivity_plus` falle (PDA / ethernet).
  bool get _attemptRemoteSave =>
      !_forceOffline &&
      (_connectivityOk ||
          (_apiOkBypassUntil != null &&
              DateTime.now().isBefore(_apiOkBypassUntil!)));

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

  void _kickApiReachProbes() {
    if (!mounted || _forceOffline || _connectivityOk) {
      _apiReachProbeTimer?.cancel();
      _apiReachProbeTimer = null;
      return;
    }
    _apiReachProbeTimer?.cancel();
    _apiReachProbeTimer =
        Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_runApiReachProbe());
    });
    unawaited(_runApiReachProbe());
  }

  Future<void> _runApiReachProbe() async {
    if (!mounted || _forceOffline || _connectivityOk) {
      _apiReachProbeTimer?.cancel();
      _apiReachProbeTimer = null;
      return;
    }
    final o = await _apiService.checkReachability();
    fieldLog('Reachability', o.logLine);
    if (!mounted) return;
    if (o.ok) {
      setState(() {
        _apiOkBypassUntil =
            DateTime.now().add(const Duration(minutes: 6));
      });
      _apiReachProbeTimer?.cancel();
      _apiReachProbeTimer = null;
    }
  }

  bool _syncBusy = false;
  List<Visita> _visitas = [];
  OperationalScope? _operationalScope;
  int? _rutaIdActiva;

  /// Tras confirmar el cierre: cumplimiento y conteos (persistencia mock en estado).
  double? _porcentajeCumplimiento;
  int? _clientesVisitadosCierre;
  int? _clientesPendientesCierre;
  int _deadLetterCount = 0;
  int? _georefPendientesKpi;
  bool _georefKpiCargando = false;
  final _crashRecovery = CrashRecoveryService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vendedorService = widget.vendedorService ?? VendedorService();
    _syncService = widget.syncService ?? SyncService();
    _syncService.bindVendedor(widget.vendedorCodigo);
    _locationService = widget.locationService ?? LocationService();
    _apiService = widget.apiService ?? ApiService();
    _authService = widget.authService ?? DistribuidoraAuthService();
    _telemetry = OperationalTelemetryService(
      vendedorId: widget.vendedorCodigo,
      api: _apiService,
      locationService: _locationService,
    );
    _georefService = GeorefService(
      api: _apiService,
      vendedorService: _vendedorService,
      queue: _telemetry.queueForRecovery,
      onEnqueuedForSync: () => _telemetry.flushOutboxBackground(),
    );
    _telemetry.bindVisitasContext(
      pendingVisitasCount: () => _visitasPendientesSync,
      onPeriodicVisitaSync: _syncPendientesSilencioso,
    );
    _rutaFuture = Future<List<Visita>>.value([]);
    unawaited(GeorefLocalStore.purgeLegacyPendingCountCaches());
    unawaited(_cargarKpiGeorefDesdeCache());
    unawaited(_inicializarSesionVendedor().then((_) {
      if (!mounted) return;
      _rutaFuture = _cargarRutaDesdeApi();
      _rutaFuture.then((list) {
        if (mounted) setState(() => _visitas = list);
      });
      unawaited(_actualizarKpiGeoref());
    }));
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final previousOk = _connectivityOk;
      final ok = _hayRedDatos(results);
      if (!mounted) return;
      setState(() {
        _connectivityOk = ok;
        if (ok) {
          _apiOkBypassUntil = null;
          _apiReachProbeTimer?.cancel();
          _apiReachProbeTimer = null;
        }
      });
      _scheduleRefrescarEstadoOperacional();
      if (!ok) {
        _kickApiReachProbes();
      }
      if (!context.mounted) return;
      if (ok && !previousOk && !_forceOffline) {
        unawaited(_telemetry.onConnectivityRestored());
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
      if (!mounted) return;
      setState(() => _connectivityOk = ok);
      if (!ok) {
        _kickApiReachProbes();
      }
    });
    _scheduleRefrescarEstadoOperacional();
    _operacionalRefreshTimer = Timer.periodic(
      TelemetryConfig.operacionalUiRefreshInterval,
      (_) => _scheduleRefrescarEstadoOperacional(),
    );
    _outboxBackgroundFlushTimer = Timer.periodic(
      TelemetryConfig.outboxFlushInterval,
      (_) {
        if (_connectivityOk && !_forceOffline) {
          unawaited(_telemetry.flushOutboxBackground());
        }
      },
    );
    TimerRegistry.instance.register(
      name: 'outbox_background_flush',
      owner: 'VendedorHomeScreen',
    );
    TimerRegistry.instance.register(
      name: 'operacional_ui_refresh',
      owner: 'VendedorHomeScreen',
    );
  }

  Future<void> _inicializarSesionVendedor() async {
    final activation = await SessionManager.instance.activateForLogin(
      widget.vendedorCodigo,
      preserveSessionIfSameVendor: true,
    );
    if (activation.vendorChanged) {
      _limpiarEstadoRuntime();
      fieldLog(
        'Session',
        'cambio vendedor → runtime limpio (${widget.vendedorCodigo})',
      );
    }
    _operationalScope = OperationalScope(
      vendedorId: widget.vendedorCodigo,
      fechaOperativa: _fechaOperativaHoy,
      rutaId: _rutaIdActiva,
    );
    _telemetry.bindOperationalScope(_operationalScope);
    _syncService.bindOperationalScope(_operationalScope);
    if (!mounted) return;
    await _prefetchVisitasDesdeDisco();
    await _ejecutarRecuperacionTrasCrash();
  }

  Future<void> _ejecutarRecuperacionTrasCrash() async {
    final scope = _operationalScope ?? _scopeActual;
    final report = await _crashRecovery.recover(
      scope: scope,
      syncService: _syncService,
      vendedorService: _vendedorService,
      queue: _telemetry.queueForRecovery,
      runtimeVisitas: _visitas,
    );
    if (!mounted) return;
    setState(() {
      _visitas = report.visitas;
      _deadLetterCount = report.deadLetterCount;
      _rutaFuture = Future<List<Visita>>.value(report.visitas);
    });
    if (report.hasDeadLetters && mounted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Hay ${report.deadLetterCount} registro(s) que no se pudieron enviar. '
            'Usa sincronización forzada o contacta soporte.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  String get _fechaOperativaHoy => OperationalScope.fechaFromDateTime(DateTime.now());

  OperationalScope get _scopeActual => OperationalScope(
        vendedorId: widget.vendedorCodigo,
        fechaOperativa: _fechaOperativaHoy,
        rutaId: _rutaIdActiva,
      );

  Future<void> _actualizarScopeOperacional({int? rutaId}) async {
    if (rutaId != null && rutaId >= 1) {
      _rutaIdActiva = rutaId;
    }
    _operationalScope = _scopeActual;
    await SessionManager.instance.setOperationalScope(_operationalScope!);
    _telemetry.bindOperationalScope(_operationalScope);
    _syncService.bindOperationalScope(_operationalScope);
  }

  /// Si cambió el día calendario, descarta estado en memoria y recarga scope nuevo.
  Future<bool> _detectarCambioDiaOperativo() async {
    final hoy = _fechaOperativaHoy;
    final prev = _operationalScope?.fechaOperativa;
    if (prev == null || prev == hoy) return false;
    fieldLog('Scope', 'cambio día operativo $prev → $hoy');
    setState(() {
      _limpiarEstadoRuntime();
      _rutaIdActiva = null;
      _operationalScope = OperationalScope(
        vendedorId: widget.vendedorCodigo,
        fechaOperativa: hoy,
      );
    });
    _telemetry.bindOperationalScope(_operationalScope);
    await SessionManager.instance.setOperationalScope(_operationalScope!);
    _programarRecargaRuta();
    return true;
  }

  void _limpiarEstadoRuntime() {
    _visitas = [];
    _operationalScope = null;
    _rutaIdActiva = null;
    _georefPendientesKpi = null;
    _georefKpiCargando = false;
    _routeStarted = false;
    _routeFinished = false;
    _porcentajeCumplimiento = null;
    _clientesVisitadosCierre = null;
    _clientesPendientesCierre = null;
    _operacionalNotifier.value = null;
    _syncBusy = false;
  }

  void _scheduleRefrescarEstadoOperacional() {
    _operacionalDebounce?.cancel();
    _operacionalDebounce = Timer(
      TelemetryConfig.operacionalDebounce,
      () => unawaited(_refrescarEstadoOperacional()),
    );
  }

  int get _visitasPendientesSync => _visitas
      .where(
        (v) =>
            v.syncStatus == SyncStatus.pendingSync ||
            v.syncStatus == SyncStatus.syncError,
      )
      .length;

  Future<void> _refrescarEstadoOperacional() async {
    if (!mounted) return;
    final snap = await _telemetry.loadStatusSnapshot(
      enRuta: _routeStarted && !_routeFinished,
      puedeEnviarAlServidor: _attemptRemoteSave,
      sincronizando: _syncBusy || _telemetry.isQueueFlushing,
      visitasPendientes: _visitasPendientesSync,
    );
    if (!mounted) return;
    _operacionalNotifier.value = snap;
    if (mounted && snap.deadLetterCount != _deadLetterCount) {
      setState(() => _deadLetterCount = snap.deadLetterCount);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _telemetry.stop();
    _operacionalNotifier.dispose();
    _operacionalDebounce?.cancel();
    _resumeDebounce?.cancel();
    _operacionalRefreshTimer?.cancel();
    _outboxBackgroundFlushTimer?.cancel();
    TimerRegistry.instance.unregister('outbox_background_flush');
    TimerRegistry.instance.unregister('operacional_ui_refresh');
    _apiReachProbeTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_persistirEstadoAlPausar());
    }
    if (state == AppLifecycleState.resumed) {
      _resumeDebounce?.cancel();
      _resumeDebounce = Timer(const Duration(milliseconds: 800), () {
        if (mounted) unawaited(_onAppResumed());
      });
    }
  }

  Future<void> _persistirEstadoAlPausar() async {
    final scope = _operationalScope ?? _scopeActual;
    if (_visitas.isNotEmpty) {
      await _vendedorService.persistVisitasToDisk(scope, _visitas);
      fieldLog(
        'Lifecycle',
        'visitas persistidas al pausar scope=$scope n=${_visitas.length}',
      );
    }
    for (final v in _visitas) {
      if (v.requiereRespaldoOutbox) {
        await _telemetry.backupPendingVisita(v);
      }
    }
    await _telemetry.onAppPaused();
  }

  Future<void> _prefetchVisitasDesdeDisco() async {
    final scope = _operationalScope ?? _scopeActual;
    final cached = await _vendedorService.loadVisitasFromDisk(scope);
    if (!mounted || cached == null || cached.isEmpty) return;
    setState(() => _visitas = List<Visita>.from(cached));
  }

  Future<void> _onAppResumed() async {
    if (await _detectarCambioDiaOperativo()) return;
    await _restaurarVisitasDesdeDisco();
    if (!mounted || _syncBusy || _forceOffline) return;
    final hayPendientes = _visitas.any(
      (v) =>
          v.syncStatus == SyncStatus.pendingSync ||
          v.syncStatus == SyncStatus.syncError,
    );
    if (!hayPendientes || !_attemptRemoteSave) return;
    final reach = await _apiService.checkReachability();
    fieldLog('Resume', reach.logLine);
    if (!mounted || !reach.ok) return;
    setState(() => _syncBusy = true);
    try {
      final r = await _syncService.forceSyncPending(_visitas, _apiService);
      if (!mounted) return;
      setState(() {
        _visitas = r.visitas;
        _rutaFuture = Future<List<Visita>>.value(r.visitas);
      });
      unawaited(
        _vendedorService.persistVisitasToDisk(
          _operationalScope ?? _scopeActual,
          r.visitas,
        ),
      );
      _scheduleRefrescarEstadoOperacional();
      if (r.syncedCount > 0 && mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sincronizados ${r.syncedCount} registro(s) al volver a la app.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _restaurarVisitasDesdeDisco() async {
    final scope = _operationalScope ?? _scopeActual;
    final disk =
        await _vendedorService.loadVisitasFromDisk(scope) ?? <Visita>[];
    if (!mounted || disk.isEmpty) return;
    setState(() {
      _visitas = VendedorService.fusionarDiscoYMemoria(
        disco: disk,
        memoria: _visitas,
      );
      _rutaFuture = Future<List<Visita>>.value(_visitas);
    });
    unawaited(
      _vendedorService.persistVisitasToDisk(scope, _visitas),
    );
  }

  /// Carga remota con respaldo en disco si falla la API (alcance operacional del día).
  Future<List<Visita>> _cargarRutaDesdeApi() async {
    final fecha = _fechaOperativaHoy;
    var scope = OperationalScope(
      vendedorId: widget.vendedorCodigo,
      fechaOperativa: fecha,
      rutaId: _rutaIdActiva,
    );

    try {
      final serverList =
          await _apiService.getRutaDelDia(fecha, widget.vendedorCodigo);
      final rutaId = OperationalScope.resolveRutaIdFromVisitas(
        serverList,
        hint: _rutaIdActiva,
      );
      if (rutaId != null) {
        await _actualizarScopeOperacional(rutaId: rutaId);
        scope = _scopeActual;
      } else {
        _operationalScope = scope;
        await SessionManager.instance.setOperationalScope(scope);
      }

      final cached =
          await _vendedorService.loadVisitasFromDisk(scope) ?? <Visita>[];
      final locales = _visitas.isEmpty
          ? cached
          : VendedorService.fusionarDiscoYMemoria(
              disco: cached,
              memoria: _visitas,
            );
      final merged = VendedorService.mergeServidorConLocales(
        servidor: serverList,
        locales: locales,
      );
      await _vendedorService.persistVisitasToDisk(scope, merged);
      fieldLog('Ruta', 'GET ok scope=$scope n=${merged.length}');
      final diag = await _telemetry.loadOutboxDiagnostics();
      final visitasSync = merged
          .where(
            (v) =>
                v.syncStatus == SyncStatus.pendingSync ||
                v.syncStatus == SyncStatus.syncError,
          )
          .length;
      OutboxObservability.instance.logScopeContext(
        event: 'ruta_cargada',
        scope: scope,
        serverClientes: serverList.length,
        cacheClientes: cached.length,
        queuePending: diag.pendingCount,
        visitasSyncPending: visitasSync,
        byType: diag.countByItemType,
      );
      return merged;
    } catch (e) {
      fieldLog('Ruta', 'GET ruta falló: $e');
      final cached = await _vendedorService.loadVisitasFromDisk(scope);
      if (cached != null && cached.isNotEmpty) {
        if (_visitas.isNotEmpty) {
          return VendedorService.fusionarDiscoYMemoria(
            disco: cached,
            memoria: _visitas,
          );
        }
        return cached;
      }
      if (_visitas.isNotEmpty) return List<Visita>.from(_visitas);
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
    unawaited(_actualizarKpiGeoref());
  }

  Future<void> _cargarKpiGeorefDesdeCache() async {
    final snap = await _georefService.loadPendientesKpi(
      scope: _operationalScope ?? _scopeActual,
      fetchRemote: false,
    );
    if (!mounted) return;
    setState(() {
      _georefPendientesKpi = snap.count;
    });
  }

  Future<void> _actualizarKpiGeoref({bool fetchRemote = true}) async {
    if (!mounted) return;
    setState(() => _georefKpiCargando = true);
    final snap = await _georefService.loadPendientesKpi(
      scope: _operationalScope ?? _scopeActual,
      fetchRemote: fetchRemote,
    );
    if (!mounted) return;
    setState(() {
      _georefPendientesKpi = snap.count;
      _georefKpiCargando = false;
    });
  }

  static Color _colorGeorefPendientesKpi(int count) {
    if (count <= 0) return const Color(0xFF2E7D32);
    if (count <= 10) return AppColors.estadoPendiente;
    return AppColors.primaryRed;
  }

  String get _georefPendientesKpiTexto {
    if (_georefKpiCargando && _georefPendientesKpi == null) return '…';
    if (_georefPendientesKpi == null) return '—';
    return '$_georefPendientesKpi';
  }

  bool get _mostrarRecordatorioGeoref =>
      _georefPendientesKpi != null && _georefPendientesKpi! > 0;

  Future<void> _cerrarSesion() async {
    _telemetry.stop();
    _limpiarEstadoRuntime();
    await _authService.logout();
    if (!mounted) return;
    if (!context.mounted) return;
    replaceWithDistribuidoraLogin(context);
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

  Visita? get _proximaParada {
    final pendientes = _visitas
        .where((v) => v.estado == VisitaEstado.pendiente)
        .toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));
    return pendientes.isEmpty ? null : pendientes.first;
  }

  int get _indiceClienteActual {
    if (_totalClientes <= 0) return 0;
    final atendidos = _clientesAtendidos;
    if (atendidos >= _totalClientes) return _totalClientes;
    return atendidos + 1;
  }

  void _abrirOutboxDebug() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OutboxDebugScreen(
          telemetry: _telemetry,
          vendedorId: widget.vendedorCodigo,
          scope: _operationalScope ?? _scopeActual,
          serverClientes: _visitas.length,
          cacheClientes: _visitas.length,
        ),
      ),
    );
  }

  /// Fusiona actualizaciones por `id` y agrega paradas nuevas del servidor.
  static List<Visita> _mergeVisitasPorId(List<Visita> base, List<Visita> updates) {
    if (updates.isEmpty) return List<Visita>.from(base);
    final fresh = <String, Visita>{for (final u in updates) u.id: u};
    final baseIds = base.map((e) => e.id).toSet();
    final merged = [for (final b in base) fresh[b.id] ?? b];
    for (final u in updates) {
      if (!baseIds.contains(u.id)) merged.add(u);
    }
    merged.sort((a, b) => a.orden.compareTo(b.orden));
    return merged;
  }

  Future<List<Visita>> _persistVisitaWriteAhead(
    Visita updated,
    List<Visita> current,
  ) async {
    final scope = _operationalScope ?? _scopeActual;
    final wa = WriteAheadVisitSync(
      vendedorService: _vendedorService,
      telemetry: _telemetry,
    );
    return wa.persistAndEnqueue(
      scope: scope,
      visitas: current,
      updated: updated,
    );
  }

  void _setVisitas(List<Visita> next) {
    final merged = _mergeVisitasPorId(_visitas, next);
    setState(() {
      _visitas = merged;
      _rutaFuture = Future<List<Visita>>.value(merged);
    });
    unawaited(
      _vendedorService.persistVisitasToDisk(
        _operationalScope ?? _scopeActual,
        merged,
      ),
    );
    _scheduleRefrescarEstadoOperacional();
  }

  void _iniciarRuta() {
    setState(() {
      _routeStarted = true;
      _routeFinished = false;
      _porcentajeCumplimiento = null;
      _clientesVisitadosCierre = null;
      _clientesPendientesCierre = null;
    });
    _telemetry.startEnRuta();
    _scheduleRefrescarEstadoOperacional();
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
    _telemetry.stop();
    _scheduleRefrescarEstadoOperacional();

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

  Future<void> _abrirGeorefPendientes() async {
    final scope = _operationalScope ?? _scopeActual;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => GeorefPendientesScreen(
          scope: scope,
          georefService: _georefService,
          locationService: _locationService,
          interfaceConnectivityDetected: _connectivityOk,
          attemptRemoteSave: _attemptRemoteSave,
        ),
      ),
    );
    if (!mounted) return;
    await _actualizarKpiGeoref();
  }

  Future<void> _abrirRuta({RutaListaFiltro filtro = RutaListaFiltro.todos}) async {
    // Al abrir terreno: intento único de API si connectivity_plus falla (PDA / ethernet).
    if (!_attemptRemoteSave && !_forceOffline) {
      final o = await _apiService.checkReachability();
      // ignore: avoid_print
      fieldLog('Abrir ruta', o.logLine);
      if (!mounted) return;
      if (o.ok) {
        setState(() {
          _apiOkBypassUntil =
              DateTime.now().add(const Duration(minutes: 6));
        });
      }
    }
    if (!mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RutaScreen(
          visitas: List<Visita>.from(_visitas),
          attemptRemoteSave: _attemptRemoteSave,
          interfaceConnectivityDetected: _connectivityOk,
          locationService: _locationService,
          vendedorService: _vendedorService,
          syncService: _syncService,
          apiService: _apiService,
          operationalScope: _operationalScope ?? _scopeActual,
          georefService: _georefService,
          filtroLista: filtro,
          onVisitasChanged: _setVisitas,
          reloadRuta: _cargarRutaDesdeApi,
          persistVisitaWriteAhead: _persistVisitaWriteAhead,
        ),
      ),
    );
  }

  void _mostrarResumenDia() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            20 + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '📊 Resumen del día',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              RutaProgresoCard(
                atendidos: _clientesAtendidos,
                total: _totalClientes,
                visitados: _visitados,
                incidencias: _incidencias,
                pendientes: _pendientes,
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ResumenDiaTile(
                      valor: '$_visitados',
                      etiqueta: 'Visitados',
                      color: AppColors.secondaryBlue,
                      icon: Icons.check_circle_outline,
                    ),
                  ),
                  const SizedBox(width: 8),
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
            ],
          ),
        );
      },
    );
  }

  static final Uri _urlCatalogo = Uri.parse('https://cat.quillotana.cl');
  static final Uri _urlBsale =
      Uri.parse('https://app.bsale.cl/documents/sales');

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

  Future<void> _syncPendientesSilencioso() async {
    if (_syncBusy || _forceOffline || !_attemptRemoteSave) return;
    final hay = _visitas.any(
      (v) =>
          v.syncStatus == SyncStatus.pendingSync ||
          v.syncStatus == SyncStatus.syncError,
    );
    if (!hay) return;
    final reach = await _apiService.checkReachability();
    if (!reach.ok) return;
    _syncBusy = true;
    try {
      final r = await _syncService.forceSyncPending(_visitas, _apiService);
      if (!mounted) return;
      setState(() {
        _visitas = r.visitas;
        _rutaFuture = Future<List<Visita>>.value(r.visitas);
      });
      await _vendedorService.persistVisitasToDisk(
        _operationalScope ?? _scopeActual,
        r.visitas,
      );
      fieldLog(
        'Sync',
        'periódico: ${r.syncedCount} ok, ${r.errorCount} error, '
        '${r.pendingAfterCount} pendiente(s)',
      );
      _scheduleRefrescarEstadoOperacional();
      unawaited(_actualizarKpiGeoref());
    } finally {
      if (mounted) {
        setState(() => _syncBusy = false);
        _scheduleRefrescarEstadoOperacional();
      }
    }
  }

  Future<void> _sincronizacionForzada() async {
    if (_syncBusy) return;
    if (_forceOffline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Envío en línea desactivado en esta sesión.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _syncBusy = true);
    try {
      final reach = await _apiService.checkReachability();
      // ignore: avoid_print
      fieldLog('Sync forzado', reach.logLine);
      if (!mounted) return;
      if (!reach.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reach.userMessage),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      setState(() {
        _apiOkBypassUntil =
            DateTime.now().add(const Duration(minutes: 6));
      });
      final r = await _syncService.forceSyncPending(_visitas, _apiService);
      if (!mounted) return;
      setState(() {
        _visitas = r.visitas;
        _rutaFuture = Future<List<Visita>>.value(r.visitas);
      });
      unawaited(
        _vendedorService.persistVisitasToDisk(
          _operationalScope ?? _scopeActual,
          r.visitas,
        ),
      );
      _scheduleRefrescarEstadoOperacional();

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
        if (r.errorDetails.isNotEmpty) {
          lineas.add('');
          lineas.addAll(r.errorDetails.map((e) => e.userMessage));
        }
        if (r.pendingAfterCount > 0 || r.syncErrorAfterCount > 0) {
          lineas.add(
            'En cola: ${r.pendingAfterCount} pendiente(s) de envío'
            '${r.syncErrorAfterCount > 0 ? ', ${r.syncErrorAfterCount} con estado error antiguo' : ''}.',
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
          content: SingleChildScrollView(
            child: Text(mensaje),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      unawaited(_actualizarKpiGeoref());
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
          TerrenoEnlaceChip(
            canSyncWithServer: _attemptRemoteSave,
            interfaceConnectivityDetected: _connectivityOk,
            anyItemSyncing: _visitas.any(
              (v) => v.syncStatus == SyncStatus.syncing,
            ),
            batchSyncing: _syncBusy,
          ),
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: 'Debug outbox',
              onPressed: _abrirOutboxDebug,
            ),
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
                  'Día operativo: ${Visita.nombreDiaCalendario(ahora)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_mostrarRecordatorioGeoref) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _abrirGeorefPendientes,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '📍 Tienes $_georefPendientesKpi '
                              '${_georefPendientesKpi == 1 ? 'cliente' : 'clientes'} '
                              'pendiente${_georefPendientesKpi == 1 ? '' : 's'} '
                              'de georreferenciar',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.3,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 22,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (!_routeStarted && !_routeFinished) ...[
                  FilledButton.icon(
                    onPressed: _iniciarRuta,
                    icon: const Icon(Icons.local_shipping_outlined, size: 26),
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
                    onPressed: () => _abrirRuta(),
                    icon: const Icon(Icons.local_shipping_outlined, size: 26),
                    label: const Text('Continuar ruta'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _solicitarFinalizarRuta,
                    icon: const Icon(Icons.flag_rounded),
                    label: const Text('Finalizar ruta'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      foregroundColor: AppColors.primaryRed,
                      side: const BorderSide(
                        color: AppColors.primaryRed,
                        width: 1.5,
                      ),
                      backgroundColor: AppColors.surface,
                    ),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: () => _abrirRuta(),
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
                const SizedBox(height: 20),
                Text(
                  'Estado en terreno',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 10),
                OperationalStatusListener(
                  snapshotListenable: _operacionalNotifier,
                  onOpenOutboxDebug: _abrirOutboxDebug,
                ),
                if (_routeStarted && !_routeFinished) ...[
                  const SizedBox(height: 16),
                  RutaActivaCard(
                    visible: true,
                    clienteActual: _indiceClienteActual,
                    totalClientes: _totalClientes,
                    proximaParadaNombre: _proximaParada?.clienteNombre,
                  ),
                ],
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
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ResumenDiaTile(
                        valor: '$_visitados',
                        etiqueta: 'Visitados',
                        color: AppColors.secondaryBlue,
                        icon: Icons.check_circle_outline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ResumenDiaTile(
                        valor: '$_incidencias',
                        etiqueta: 'Incidencias',
                        color: AppColors.primaryRed,
                        icon: Icons.warning_amber_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ResumenDiaTile(
                        valor: _georefPendientesKpiTexto,
                        etiqueta: 'Georef pend.',
                        color: _colorGeorefPendientesKpi(
                          _georefPendientesKpi ?? 0,
                        ),
                        icon: Icons.add_location_alt_outlined,
                        onTap: _abrirGeorefPendientes,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                RutaProgresoCard(
                  atendidos: _clientesAtendidos,
                  total: _totalClientes,
                  visitados: _visitados,
                  incidencias: _incidencias,
                  pendientes: _pendientes,
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
                if (_routeFinished) ...[
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: AppColors.secondaryBlue.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(
                            Icons.task_alt_rounded,
                            color: theme.colorScheme.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _porcentajeCumplimiento != null
                                      ? 'Ruta finalizada · '
                                          '${_porcentajeCumplimiento!.toStringAsFixed(1)}% cumplimiento'
                                      : 'Ruta finalizada',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (_clientesVisitadosCierre != null &&
                                    _clientesPendientesCierre != null)
                                  Text(
                                    '$_clientesVisitadosCierre atendidos · '
                                    '$_clientesPendientesCierre pendientes',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_visitas.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _abrirRuta(),
                          icon: const Icon(Icons.people_outline, size: 22),
                          label: const Text('Clientes'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 50),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _abrirRuta(
                            filtro: RutaListaFiltro.soloIncidencias,
                          ),
                          icon: const Icon(Icons.warning_amber_rounded, size: 22),
                          label: const Text('Incidencias'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 50),
                            foregroundColor: AppColors.primaryRed,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _mostrarResumenDia,
                    icon: const Icon(Icons.bar_chart_rounded, size: 22),
                    label: const Text('Resumen'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
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
                  onPressed: _syncBusy ? null : _sincronizacionForzada,
                  icon: _syncBusy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded, size: 24),
                  label: Text(
                    _syncBusy ? 'Sincronizando…' : 'Sincronización forzada',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
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
          return bodyContent;
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

}

class _ResumenDiaTile extends StatelessWidget {
  const _ResumenDiaTile({
    required this.valor,
    required this.etiqueta,
    required this.color,
    required this.icon,
    this.onTap,
  });

  final String valor;
  final String etiqueta;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Padding(
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
    );
    return Material(
      color: AppColors.surface,
      elevation: 1,
      shadowColor: AppColors.secondaryBlue.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: onTap == null
          ? child
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: child,
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

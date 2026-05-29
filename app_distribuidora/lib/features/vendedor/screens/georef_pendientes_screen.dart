import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/session/operational_scope.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ux/offline_ux.dart';
import '../models/georef_pendiente.dart';
import '../services/georef_service.dart';
import '../services/location_service.dart';
import '../widgets/visit_action_sheets.dart';

/// Lista de clientes con georef pendiente o captura local.
class GeorefPendientesScreen extends StatefulWidget {
  const GeorefPendientesScreen({
    super.key,
    required this.scope,
    required this.georefService,
    required this.locationService,
    required this.interfaceConnectivityDetected,
    required this.attemptRemoteSave,
  });

  final OperationalScope scope;
  final GeorefService georefService;
  final LocationService locationService;
  final bool interfaceConnectivityDetected;
  final bool attemptRemoteSave;

  @override
  State<GeorefPendientesScreen> createState() => _GeorefPendientesScreenState();
}

class _GeorefPendientesScreenState extends State<GeorefPendientesScreen> {
  List<GeorefPendiente> _items = [];
  bool _loading = true;
  String? _capturandoClave;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final list = await widget.georefService.loadPendientes(
      scope: widget.scope,
    );
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _capturar(GeorefPendiente item) async {
    setState(() => _capturandoClave = item.claveLocal);
    try {
      final fast = OfflineUx.debeOmitirHttp(
        interfaceConnectivityDetected: widget.interfaceConnectivityDetected,
        attemptRemoteSave: widget.attemptRemoteSave,
        forceOffline: false,
      );
      final snap = await captureGpsSnapshot(
        widget.locationService,
        'Georef',
        fastOffline: fast,
      );
      if (snap == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo obtener ubicación. Intenta en campo abierto.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final result = await widget.georefService.capturarUbicacion(
        scope: widget.scope,
        item: item,
        lat: snap.latitude,
        lon: snap.longitude,
        omitirHttp: fast,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.mensajeUsuario),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _reload();
    } finally {
      if (mounted) setState(() => _capturandoClave = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes sin georreferencia'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No hay clientes pendientes de georreferencia.',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final item = _items[i];
                      final busy = _capturandoClave == item.claveLocal;
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: AppColors.secondaryBlue.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                item.clienteNombre,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(item.direccion),
                              if (item.comuna != null &&
                                  item.comuna!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  item.comuna!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                item.estadoUiLabel,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: busy ? null : () => _capturar(item),
                                icon: busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.add_location_alt_outlined),
                                label: const Text('Guardar ubicación'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

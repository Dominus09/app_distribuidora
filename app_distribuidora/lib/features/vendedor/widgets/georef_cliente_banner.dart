import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/session/operational_scope.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ux/offline_ux.dart';
import '../models/georef_origen.dart';
import '../models/georef_pendiente.dart';
import '../models/visita.dart';
import '../screens/georef_mapa_screen.dart';
import '../services/georef_service.dart';
import '../services/location_service.dart';
import '../utils/georef_pendiente_filter.dart';
import 'visit_action_sheets.dart';

/// Banner y acciones rápidas cuando el cliente no tiene georef efectiva.
class GeorefClienteBanner extends StatelessWidget {
  const GeorefClienteBanner({
    super.key,
    required this.visita,
    required this.scope,
    required this.georefService,
    required this.locationService,
    required this.interfaceConnectivityDetected,
    required this.attemptRemoteSave,
    this.onGeorefGuardada,
  });

  final Visita visita;
  final OperationalScope scope;
  final GeorefService georefService;
  final LocationService locationService;
  final bool interfaceConnectivityDetected;
  final bool attemptRemoteSave;
  final ValueChanged<Visita>? onGeorefGuardada;

  bool get _sinGeoref =>
      georefPendienteRequiereCaptura(GeorefPendiente.fromVisita(visita));

  @override
  Widget build(BuildContext context) {
    if (!_sinGeoref) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final item = GeorefPendiente.fromVisita(visita);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.estadoPendiente.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.estadoPendiente.withValues(alpha: 0.55),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.onSurface,
                size: 26,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⚠ Cliente sin georreferencia',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _capturarGps(context, item),
            icon: const Icon(Icons.my_location),
            label: const Text('📍 Capturar GPS'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _abrirMapa(context, item),
            icon: const Icon(Icons.map_outlined),
            label: const Text('🗺 Asignar desde mapa'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _capturarGps(BuildContext context, GeorefPendiente item) async {
    final fast = OfflineUx.debeOmitirHttp(
      interfaceConnectivityDetected: interfaceConnectivityDetected,
      attemptRemoteSave: attemptRemoteSave,
      forceOffline: false,
    );
    final snap = await captureGpsSnapshot(
      locationService,
      'Georef',
      fastOffline: fast,
    );
    if (snap == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo obtener ubicación GPS.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final result = await georefService.capturarUbicacion(
      scope: scope,
      item: item,
      lat: snap.latitude,
      lon: snap.longitude,
      origen: GeorefOrigen.gpsTerreno,
      omitirHttp: fast,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.mensajeUsuario),
        behavior: SnackBarBehavior.floating,
      ),
    );
    onGeorefGuardada?.call(
      visita.copyWith(latCliente: snap.latitude, lonCliente: snap.longitude),
    );
  }

  Future<void> _abrirMapa(BuildContext context, GeorefPendiente item) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => GeorefMapaScreen(
          item: item,
          scope: scope,
          georefService: georefService,
          interfaceConnectivityDetected: interfaceConnectivityDetected,
          attemptRemoteSave: attemptRemoteSave,
        ),
      ),
    );
    if (ok == true && context.mounted) {
      onGeorefGuardada?.call(visita);
    }
  }
}

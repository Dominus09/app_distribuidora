import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/session/operational_scope.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ux/offline_ux.dart';
import '../models/georef_origen.dart';
import '../models/georef_pendiente.dart';
import '../services/address_geocoder.dart';
import '../services/georef_service.dart';

/// Asignación manual de georef sobre mapa (pin movible).
class GeorefMapaScreen extends StatefulWidget {
  const GeorefMapaScreen({
    super.key,
    required this.item,
    required this.scope,
    required this.georefService,
    required this.interfaceConnectivityDetected,
    required this.attemptRemoteSave,
    AddressGeocoder? geocoder,
  }) : _geocoder = geocoder;

  final GeorefPendiente item;
  final OperationalScope scope;
  final GeorefService georefService;
  final bool interfaceConnectivityDetected;
  final bool attemptRemoteSave;
  final AddressGeocoder? _geocoder;

  @override
  State<GeorefMapaScreen> createState() => _GeorefMapaScreenState();
}

class _GeorefMapaScreenState extends State<GeorefMapaScreen> {
  static const _markerId = MarkerId('georef_pin');

  GoogleMapController? _mapController;
  LatLng _pinPosition = AddressGeocoder.defaultChile;
  bool _loadingMap = true;
  bool _saving = false;
  bool _geocoded = false;
  String? _geocodeHint;

  AddressGeocoder get _geocoder =>
      widget._geocoder ?? AddressGeocoder();

  @override
  void initState() {
    super.initState();
    unawaited(_initMapCenter());
  }

  Future<void> _initMapCenter() async {
    final item = widget.item;
    LatLng? center;

    if (item.tieneCoordenadasEfectivas) {
      center = LatLng(item.latEfectiva, item.lonEfectiva);
      _geocoded = false;
      _geocodeHint = 'Coordenadas existentes como referencia inicial.';
    } else {
      center = await _geocoder.geocode(
        direccion: item.direccion,
        comuna: item.comuna,
        ciudad: item.ciudad,
      );
      if (center != null) {
        _geocoded = true;
        _geocodeHint = 'Centrado según dirección del cliente.';
      } else {
        _geocoded = false;
        _geocodeHint =
            'No se encontró la dirección. Ajusta el pin manualmente.';
        center = AddressGeocoder.defaultChile;
      }
    }

    if (!mounted) return;
    setState(() {
      _pinPosition = center!;
      _loadingMap = false;
    });
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_pinPosition, _geocoded ? 16 : 11),
    );
  }

  Future<void> _guardar() async {
    setState(() => _saving = true);
    try {
      final omitirHttp = OfflineUx.debeOmitirHttp(
        interfaceConnectivityDetected: widget.interfaceConnectivityDetected,
        attemptRemoteSave: widget.attemptRemoteSave,
        forceOffline: false,
      );
      final result = await widget.georefService.capturarUbicacion(
        scope: widget.scope,
        item: widget.item,
        lat: _pinPosition.latitude,
        lon: _pinPosition.longitude,
        origen: GeorefOrigen.mapaManual,
        omitirHttp: omitirHttp,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.mensajeUsuario),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Asignar desde mapa'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.clienteNombre,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(item.direccion),
                if (item.comuna != null && item.comuna!.isNotEmpty)
                  Text(
                    item.comuna!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (item.ciudad != null && item.ciudad!.isNotEmpty)
                  Text(
                    item.ciudad!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  GeorefOrigen.mapaManual.uxHint,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.estadoPendiente,
                  ),
                ),
                if (_geocodeHint != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _geocodeHint!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (_loadingMap)
                  const Center(child: CircularProgressIndicator())
                else
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _pinPosition,
                      zoom: _geocoded ? 16 : 11,
                    ),
                    onMapCreated: (c) => _mapController = c,
                    markers: {
                      Marker(
                        markerId: _markerId,
                        position: _pinPosition,
                        draggable: true,
                        onDragEnd: (pos) =>
                            setState(() => _pinPosition = pos),
                      ),
                    },
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: true,
                    mapToolbarEnabled: false,
                  ),
                if (!_loadingMap)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(10),
                      color: theme.colorScheme.surface.withValues(alpha: 0.95),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(
                          'Arrastra el pin para ajustar la ubicación.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: _loadingMap || _saving ? null : _guardar,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt_outlined),
                label: const Text('Guardar georreferencia'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

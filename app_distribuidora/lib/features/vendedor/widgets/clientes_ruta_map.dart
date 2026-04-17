import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/visita.dart';
import '../services/location_service.dart';
import '../services/ruta_map_geolocator.dart';

/// Mapa de la ruta: marcadores simples por estado, nombre en ventana nativa.
class ClientesRutaMap extends StatefulWidget {
  const ClientesRutaMap({
    super.key,
    required this.visitas,
    required this.locationService,
    this.focusedVisitaId,
    this.height = 220,
    this.expand = false,
    this.centerOnFirstPending = false,
  });

  final List<Visita> visitas;
  final LocationService locationService;
  final String? focusedVisitaId;
  final double height;
  final bool expand;
  final bool centerOnFirstPending;

  @override
  ClientesRutaMapState createState() => ClientesRutaMapState();
}

class ClientesRutaMapState extends State<ClientesRutaMap> {
  GoogleMapController? _controller;
  LatLng? _userLatLng;

  static const LatLng _quito = LatLng(-0.22985, -78.52495);

  @override
  void initState() {
    super.initState();
    unawaited(_refreshUserLocation());
  }

  @override
  void didUpdateWidget(ClientesRutaMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_visitasStopsLocationEqual(oldWidget.visitas, widget.visitas)) {
      _refreshMarkersFit();
    }
    if (widget.focusedVisitaId != oldWidget.focusedVisitaId) {
      _animateToFocused();
    }
  }

  static bool _visitasStopsLocationEqual(List<Visita> a, List<Visita> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].latCliente != b[i].latCliente ||
          a[i].lonCliente != b[i].lonCliente ||
          a[i].nombreFantasia != b[i].nombreFantasia) {
        return false;
      }
    }
    return true;
  }

  Future<void> _refreshUserLocation() async {
    final device = await RutaMapGeolocator.tryDeviceLatLng();
    if (!mounted) return;
    if (device != null) {
      setState(() => _userLatLng = device);
      return;
    }
    final gpsOk = await widget.locationService.isGpsAvailable();
    if (!gpsOk || !mounted) return;
    final snap = await widget.locationService.getCurrentPosition();
    if (!mounted) return;
    setState(() => _userLatLng = LatLng(snap.latitude, snap.longitude));
  }

  Future<void> _refreshMarkersFit() async {
    await _refreshUserLocation();
    if (_controller == null || !mounted) return;
    await _fitCameraToMarkers();
  }

  double _markerHue(VisitaEstado e) => switch (e) {
        VisitaEstado.pendiente => BitmapDescriptor.hueYellow,
        VisitaEstado.visitado => BitmapDescriptor.hueAzure,
        VisitaEstado.incidencia => BitmapDescriptor.hueRed,
      };

  Set<Marker> _buildMarkers() {
    final out = <Marker>{};
    for (final v in widget.visitas) {
      if (v.latCliente == 0 && v.lonCliente == 0) continue;
      final pos = LatLng(v.latCliente, v.lonCliente);
      final focused = widget.focusedVisitaId == v.id;
      out.add(
        Marker(
          markerId: MarkerId('cliente_${v.id}'),
          position: pos,
          zIndexInt: focused ? 2 : 1,
          icon: BitmapDescriptor.defaultMarkerWithHue(_markerHue(v.estado)),
          infoWindow: InfoWindow(
            title: v.tituloMapaCliente,
            snippet: v.estado.label,
          ),
        ),
      );
    }
    final u = _userLatLng;
    if (u != null) {
      out.add(
        Marker(
          markerId: const MarkerId('vendedor_pos'),
          position: u,
          zIndexInt: 4,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: const InfoWindow(title: 'Tu ubicación'),
        ),
      );
    }
    return out;
  }

  LatLng? _firstPendingClienteLatLng() {
    final pendientes =
        widget.visitas.where((v) => v.estado == VisitaEstado.pendiente).toList()
          ..sort((a, b) => a.orden.compareTo(b.orden));
    for (final v in pendientes) {
      if (v.latCliente == 0 && v.lonCliente == 0) continue;
      return LatLng(v.latCliente, v.lonCliente);
    }
    return null;
  }

  LatLng? _firstClienteLatLng() {
    final ordenados = [...widget.visitas]
      ..sort((a, b) => a.orden.compareTo(b.orden));
    for (final v in ordenados) {
      if (v.latCliente == 0 && v.lonCliente == 0) continue;
      return LatLng(v.latCliente, v.lonCliente);
    }
    return null;
  }

  Iterable<LatLng> _allRelevantPoints() sync* {
    for (final v in widget.visitas) {
      if (v.latCliente == 0 && v.lonCliente == 0) continue;
      yield LatLng(v.latCliente, v.lonCliente);
    }
    final u = _userLatLng;
    if (u != null) yield u;
  }

  Future<void> _fitCameraToMarkers() async {
    final c = _controller;
    if (c == null || !mounted) return;
    final pts = _allRelevantPoints().toList();
    if (pts.isEmpty) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(_quito, 12));
      return;
    }
    if (pts.length == 1) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 14.5));
      return;
    }
    double minLat = pts.first.latitude;
    double maxLat = pts.first.latitude;
    double minLon = pts.first.longitude;
    double maxLon = pts.first.longitude;
    for (final p in pts.skip(1)) {
      minLat = minLat < p.latitude ? minLat : p.latitude;
      maxLat = maxLat > p.latitude ? maxLat : p.latitude;
      minLon = minLon < p.longitude ? minLon : p.longitude;
      maxLon = maxLon > p.longitude ? maxLon : p.longitude;
    }
    final sw = LatLng(minLat, minLon);
    final ne = LatLng(maxLat, maxLon);
    await c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: sw, northeast: ne),
        56,
      ),
    );
  }

  Future<void> _animateToFocused() async {
    final id = widget.focusedVisitaId;
    final c = _controller;
    if (c == null || id == null || !mounted) return;
    Visita? match;
    for (final v in widget.visitas) {
      if (v.id == id) {
        match = v;
        break;
      }
    }
    if (match == null) return;
    if (match.latCliente == 0 && match.lonCliente == 0) return;
    await c.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(match.latCliente, match.lonCliente),
        16,
      ),
    );
  }

  Future<void> _onMapReady() async {
    await _refreshUserLocation();
    if (!mounted) return;
    final c = _controller;
    if (c == null) return;

    if (widget.focusedVisitaId != null) {
      await _fitCameraToMarkers();
      await _animateToFocused();
      return;
    }

    if (widget.centerOnFirstPending) {
      final p = _firstPendingClienteLatLng();
      if (p != null) {
        await c.animateCamera(CameraUpdate.newLatLngZoom(p, 14.5));
        return;
      }
    }

    await _fitCameraToMarkers();
    await _animateToFocused();
  }

  Future<void> centerOnFirstPending() async {
    final c = _controller;
    if (c == null || !mounted) return;
    final p = _firstPendingClienteLatLng();
    if (p != null) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(p, 15));
      return;
    }
    await _fitCameraToMarkers();
  }

  Future<void> centerOnUserLocation() async {
    await _refreshUserLocation();
    if (!mounted) return;
    final c = _controller;
    final u = _userLatLng;
    if (c == null || u == null) return;
    await c.animateCamera(CameraUpdate.newLatLngZoom(u, 16));
  }

  @override
  Widget build(BuildContext context) {
    final firstTarget = widget.centerOnFirstPending
        ? (_firstPendingClienteLatLng() ?? _firstClienteLatLng() ?? _quito)
        : (_firstClienteLatLng() ?? _quito);
    final initialZoom = firstTarget != _quito ? 14.0 : 12.0;

    final map = GoogleMap(
      initialCameraPosition: CameraPosition(
        target: firstTarget,
        zoom: initialZoom,
      ),
      markers: _buildMarkers(),
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      compassEnabled: true,
      onMapCreated: (controller) {
        _controller = controller;
        WidgetsBinding.instance.addPostFrameCallback((_) => _onMapReady());
      },
    );

    final wrapped = widget.expand
        ? map
        : ClipRRect(borderRadius: BorderRadius.circular(16), child: map);

    return widget.expand
        ? SizedBox.expand(child: wrapped)
        : SizedBox(
            height: widget.height,
            width: double.infinity,
            child: wrapped,
          );
  }
}

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/visita.dart';
import '../services/location_service.dart';

/// Mapa de la ruta: clientes (`lat_cliente` / `lon_cliente`) y posición del vendedor (servicio existente).
class ClientesRutaMap extends StatefulWidget {
  const ClientesRutaMap({
    super.key,
    required this.visitas,
    required this.locationService,
    this.focusedVisitaId,
    this.height = 220,
  });

  final List<Visita> visitas;
  final LocationService locationService;
  final String? focusedVisitaId;
  final double height;

  @override
  State<ClientesRutaMap> createState() => _ClientesRutaMapState();
}

class _ClientesRutaMapState extends State<ClientesRutaMap> {
  GoogleMapController? _controller;
  LatLng? _userLatLng;
  bool _userMarkerTried = false;

  static const LatLng _quito = LatLng(-0.22985, -78.52495);

  @override
  void initState() {
    super.initState();
    _refreshUserLocation();
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

  /// Solo reencuadra la cámara si cambian paradas o coordenadas (no en cada cambio de estado).
  static bool _visitasStopsLocationEqual(List<Visita> a, List<Visita> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].latCliente != b[i].latCliente ||
          a[i].lonCliente != b[i].lonCliente) {
        return false;
      }
    }
    return true;
  }

  Future<void> _refreshUserLocation() async {
    if (_userMarkerTried) return;
    _userMarkerTried = true;
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
        VisitaEstado.pendiente => BitmapDescriptor.hueGreen,
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
          infoWindow: InfoWindow(title: v.clienteNombre, snippet: v.direccion),
          icon: BitmapDescriptor.defaultMarkerWithHue(_markerHue(v.estado)),
        ),
      );
    }
    final u = _userLatLng;
    if (u != null) {
      out.add(
        Marker(
          markerId: const MarkerId('vendedor_pos'),
          position: u,
          zIndexInt: 3,
          infoWindow: const InfoWindow(title: 'Tu posición'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }
    return out;
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
      await c.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
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

  @override
  Widget build(BuildContext context) {
    final pts = _allRelevantPoints().toList();
    final initial = pts.isNotEmpty ? pts.first : _quito;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: initial, zoom: 13),
          markers: _buildMarkers(),
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          compassEnabled: true,
          onMapCreated: (controller) {
            _controller = controller;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fitCameraToMarkers();
              _animateToFocused();
            });
          },
        ),
      ),
    );
  }
}

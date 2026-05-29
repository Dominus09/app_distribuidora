import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Geocodificación ligera vía Nominatim (OpenStreetMap).
class AddressGeocoder {
  AddressGeocoder({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const defaultChile = LatLng(-33.0472, -71.6127);

  /// Consultas en orden de precisión (dirección completa → comuna → ciudad).
  static List<String> buildSearchQueries({
    required String direccion,
    String? comuna,
    String? ciudad,
  }) {
    final d = direccion.trim();
    final c = comuna?.trim();
    final ci = ciudad?.trim();
    final out = <String>[];

    if (d.isNotEmpty && d != '—') {
      final parts = <String>[d];
      if (c != null && c.isNotEmpty) parts.add(c);
      if (ci != null && ci.isNotEmpty) parts.add(ci);
      parts.add('Chile');
      out.add(parts.join(', '));
    }
    if (c != null && c.isNotEmpty) {
      final parts = <String>[c];
      if (ci != null && ci.isNotEmpty) parts.add(ci);
      parts.add('Chile');
      out.add(parts.join(', '));
    }
    if (ci != null && ci.isNotEmpty) {
      out.add('$ci, Chile');
    }
    return out;
  }

  Future<LatLng?> geocode({
    required String direccion,
    String? comuna,
    String? ciudad,
  }) async {
    for (final q in buildSearchQueries(
      direccion: direccion,
      comuna: comuna,
      ciudad: ciudad,
    )) {
      final hit = await _searchOne(q);
      if (hit != null) return hit;
    }
    return null;
  }

  Future<LatLng?> _searchOne(String query) async {
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      {
        'q': query,
        'format': 'json',
        'limit': '1',
        'countrycodes': 'cl',
      },
    );
    try {
      final resp = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'app_distribuidora_georef/1.0',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! Map) return null;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lon = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null || lon == null) return null;
      return LatLng(lat, lon);
    } catch (_) {
      return null;
    }
  }
}

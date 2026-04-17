import 'package:url_launcher/url_launcher.dart';

/// Abre Google Maps en modo ruta hacia el destino (sin tocar backend).
Future<bool> launchGoogleMapsDirections(double lat, double lon) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon',
  );
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

bool visitaTieneCoordenadasCliente(double lat, double lon) {
  if (lat == 0 && lon == 0) return false;
  return lat.abs() <= 90 && lon.abs() <= 180;
}

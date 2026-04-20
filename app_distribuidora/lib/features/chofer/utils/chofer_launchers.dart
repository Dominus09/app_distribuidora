import 'package:url_launcher/url_launcher.dart';

Future<bool> launchGoogleMapsDirDestino(double lat, double lng) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
  );
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Ruta con varios destinos `lat,lng/lat,lng/...` (sin cálculo ORS en app).
Future<bool> launchGoogleMapsDirSecuencia(
  List<({double lat, double lng})> puntos,
) async {
  if (puntos.isEmpty) return false;
  final path = puntos.map((p) => '${p.lat},${p.lng}').join('/');
  final uri = Uri.parse('https://www.google.com/maps/dir/$path');
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _waDigits(String telefono) {
  var d = telefono.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('56')) return d;
  if (d.startsWith('9')) return '56$d';
  return d;
}

Future<bool> launchWhatsAppReporteEntrega({
  required String telefono,
  required String nombreCliente,
  required String estadoLabel,
  required String choferNombre,
}) async {
  final digits = _waDigits(telefono);
  if (digits.isEmpty) return false;
  final hora = _fmtHora();
  final body = '🚚 Reporte de entrega\n'
      'Cliente: $nombreCliente\n'
      'Estado: $estadoLabel\n'
      'Hora: $hora\n'
      'Chofer: $choferNombre\n';
  final uri = Uri.parse(
    'https://wa.me/$digits?text=${Uri.encodeComponent(body)}',
  );
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> launchTel(String telefono) async {
  final d = telefono.replaceAll(RegExp(r'\s'), '');
  final uri = Uri.parse('tel:$d');
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _fmtHora() {
  final n = DateTime.now();
  final h = n.hour.toString().padLeft(2, '0');
  final m = n.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

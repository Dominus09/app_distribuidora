import 'package:url_launcher/url_launcher.dart';

/// Abre el marcador telefónico del dispositivo.
Future<bool> launchPhoneDialer(String telefono) async {
  final digits = telefono.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.isEmpty) return false;
  final uri = Uri(scheme: 'tel', path: digits);
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

bool tieneTelefonoLlamable(String? telefono) {
  if (telefono == null) return false;
  final d = telefono.replaceAll(RegExp(r'[^\d]'), '');
  return d.length >= 8;
}

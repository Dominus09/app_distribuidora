import '../models/visita.dart';

/// Web / plataformas sin `dart:io`: no se adjunta `foto_base64` (se mantiene `foto_url` si aplica).
Future<Map<String, dynamic>> appendFotoBase64IfPlatformSupported(
  Map<String, dynamic> body,
  Visita visita,
) async =>
    body;

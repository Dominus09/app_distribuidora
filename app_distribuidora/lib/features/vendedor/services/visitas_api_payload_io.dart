import 'dart:convert';
import 'dart:io';

import '../models/visita.dart';

/// En nativo, si `fotoPath` es ruta local, envía `foto_base64` y quita `foto_url`.
Future<Map<String, dynamic>> appendFotoBase64IfPlatformSupported(
  Map<String, dynamic> body,
  Visita visita,
) async {
  final fp = visita.fotoPath?.trim();
  if (fp == null ||
      fp.isEmpty ||
      fp.startsWith('http://') ||
      fp.startsWith('https://') ||
      fp.startsWith('mock://')) {
    return body;
  }
  final f = File(fp);
  if (!await f.exists()) return body;
  final out = Map<String, dynamic>.from(body);
  out['foto_base64'] = base64Encode(await f.readAsBytes());
  out.remove('foto_url');
  return out;
}

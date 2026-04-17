import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'incidencia_photo_native.dart'
    if (dart.library.html) 'incidencia_photo_html.dart' as impl;

/// Elige imagen y devuelve ruta persistida (nativo) o `blob:`/URL (web).
Future<String?> pickAndPersistIncidenciaPhoto({
  required ImageSource source,
  required String visitaId,
  int imageQuality = 85,
}) async {
  final picker = ImagePicker();
  final x = await picker.pickImage(
    source: source,
    imageQuality: imageQuality,
    maxWidth: 2048,
    maxHeight: 2048,
  );
  if (x == null) return null;
  return impl.persistIncidenciaPick(x, visitaId);
}

Widget buildEvidenciaFotoPreview(String path, {double maxHeight = 200}) {
  return impl.evidenciaFotoPreview(path, maxHeight);
}

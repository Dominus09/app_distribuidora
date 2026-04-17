import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copia la imagen al directorio de documentos de la app (ruta estable).
Future<String?> persistIncidenciaPick(XFile x, String visitaId) async {
  final bytes = await x.readAsBytes();
  final dir = await getApplicationDocumentsDirectory();
  final name =
      'incidencia_${visitaId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final outPath = p.join(dir.path, name);
  await File(outPath).writeAsBytes(bytes, flush: true);
  return outPath;
}

Widget evidenciaFotoPreview(String path, double maxHeight) {
  if (path.startsWith('mock://')) {
    return _mockPlaceholder(path, maxHeight);
  }
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        path,
        height: maxHeight,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _errorBox(maxHeight),
      ),
    );
  }
  final file = File(path);
  if (!file.existsSync()) {
    return _errorBox(maxHeight);
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.file(
      file,
      height: maxHeight,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => _errorBox(maxHeight),
    ),
  );
}

Widget _mockPlaceholder(String path, double maxHeight) {
  return SizedBox(
    height: maxHeight,
    child: Center(
      child: Text('Evidencia (demo)\n$path', textAlign: TextAlign.center),
    ),
  );
}

Widget _errorBox(double maxHeight) {
  return SizedBox(
    height: maxHeight,
    child: const Center(child: Text('No se pudo cargar la imagen')),
  );
}

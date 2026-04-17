import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// En web la ruta suele ser un `blob:` temporal; se guarda tal cual para la sesión.
Future<String?> persistIncidenciaPick(XFile x, String visitaId) async => x.path;

Widget evidenciaFotoPreview(String path, double maxHeight) {
  if (path.startsWith('mock://')) {
    return SizedBox(
      height: maxHeight,
      child: Center(
        child: Text('Evidencia (demo)\n$path', textAlign: TextAlign.center),
      ),
    );
  }
  if (path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('blob:')) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        path,
        height: maxHeight,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => SizedBox(
          height: maxHeight,
          child: const Center(child: Text('No se pudo cargar la imagen')),
        ),
      ),
    );
  }
  return SizedBox(
    height: maxHeight,
    child: const Center(
      child: Text('Vista previa de archivo local no disponible en web'),
    ),
  );
}

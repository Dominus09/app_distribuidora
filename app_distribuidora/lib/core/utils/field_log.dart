import 'package:flutter/foundation.dart';

final Map<String, DateTime> _lastLogAt = <String, DateTime>{};

/// Logs de terreno: solo debug; mensajes repetidos se limitan (menos spam en logcat).
void fieldLog(
  String tag,
  String message, {
  bool throttle = true,
  Duration minInterval = const Duration(seconds: 8),
  bool force = false,
}) {
  if (!kDebugMode) return;

  final key = '$tag::$message';
  if (!force && throttle) {
    final last = _lastLogAt[key];
    final now = DateTime.now();
    if (last != null && now.difference(last) < minInterval) {
      return;
    }
    _lastLogAt[key] = now;
  }

  debugPrint('[Field][$tag] $message');
}

/// Errores / eventos críticos: siempre se registran.
void fieldLogImportant(String tag, String message) {
  fieldLog(tag, message, throttle: false, force: true);
}

import 'package:flutter/foundation.dart';

/// Logs de terreno / API / sync: solo en modo debug (build de desarrollo).
/// En release (Google Play) no escribe nada → sin ruido ni datos sensibles en logcat.
void fieldLog(String tag, String message) {
  if (kDebugMode) {
    debugPrint('[Field][$tag] $message');
  }
}

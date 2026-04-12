/// Lightweight input validation helpers (no network).
abstract final class Validators {
  static String? requiredNonEmpty(String? value, {String? message}) {
    if (value == null || value.trim().isEmpty) {
      return message ?? 'Este campo es obligatorio';
    }
    return null;
  }
}

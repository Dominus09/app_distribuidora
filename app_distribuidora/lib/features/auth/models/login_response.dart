/// Respuesta de POST `/app_distribuidora/login` (contrato API).
class LoginResponse {
  const LoginResponse({
    required this.success,
    this.vendedor,
    this.nombre,
    this.tipoUsuario,
  });

  final bool success;
  /// Código del vendedor (ej. `vendedor_1`) para consultas API.
  final String? vendedor;
  /// Nombre para mostrar en la app.
  final String? nombre;
  /// Rol para routing (`vendedor`, `chofer`, `bodega`).
  final String? tipoUsuario;

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final successVal = json['success'];
    final success = successVal == true ||
        successVal == 1 ||
        successVal == 'true' ||
        successVal == '1';

    String? readStr(String a, [String? b, String? c]) {
      final v = json[a] ??
          (b != null ? json[b] : null) ??
          (c != null ? json[c] : null);
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return LoginResponse(
      success: success,
      vendedor: readStr('vendedor', 'codigo'),
      nombre: readStr('nombre', 'vendedor_nombre'),
      tipoUsuario: readStr('tipo_usuario', 'tipoUsuario', 'rol'),
    );
  }
}

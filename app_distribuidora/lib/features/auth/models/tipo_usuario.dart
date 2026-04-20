/// Rol devuelto por el login (`tipo_usuario` en API).
enum DistribuidoraRol {
  vendedor,
  chofer,
  bodega,
}

/// Convierte el texto del backend (insensible a mayúsculas / espacios).
/// Valores desconocidos → [DistribuidoraRol.vendedor] para no romper sesiones antiguas.
DistribuidoraRol rolDesdeTipoUsuario(String? raw) {
  if (raw == null || raw.trim().isEmpty) return DistribuidoraRol.vendedor;
  switch (raw.trim().toLowerCase()) {
    case 'chofer':
      return DistribuidoraRol.chofer;
    case 'bodega':
      return DistribuidoraRol.bodega;
    case 'vendedor':
      return DistribuidoraRol.vendedor;
    default:
      return DistribuidoraRol.vendedor;
  }
}

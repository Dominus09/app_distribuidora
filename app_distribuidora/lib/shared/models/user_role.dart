/// Roles used for routing after login (no API yet).
enum UserRole {
  vendedor,
  chofer,
  bodega,
  admin,
}

extension UserRoleLabel on UserRole {
  String get label => switch (this) {
        UserRole.vendedor => 'Vendedor',
        UserRole.chofer => 'Chofer',
        UserRole.bodega => 'Bodega',
        UserRole.admin => 'Admin',
      };
}

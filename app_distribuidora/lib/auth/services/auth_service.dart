import '../../shared/models/user_role.dart';

/// Authentication facade. Replace internals with API calls later.
class AuthService {
  const AuthService();

  /// Validates credentials locally until an API exists.
  Future<void> signIn({
    required String username,
    required UserRole role,
  }) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) {
      throw Exception('El nombre de usuario no puede estar vacío');
    }
    // Simulate async boundary for future HTTP.
    await Future<void>.delayed(Duration.zero);
  }
}

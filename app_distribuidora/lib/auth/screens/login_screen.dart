import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/validators.dart';
import '../../features/admin/screens/admin_home_screen.dart';
import '../../features/bodega/screens/bodega_home_screen.dart';
import '../../features/chofer/screens/chofer_home_screen.dart';
import '../../features/vendedor/screens/vendedor_home_screen.dart';
import '../../shared/models/user_role.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.authService = const AuthService()});

  final AuthService authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  UserRole _role = UserRole.vendedor;
  bool _submitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    try {
      await widget.authService.signIn(
        username: _usernameController.text,
        role: _role,
      );
      if (!mounted) return;

      final Widget destination = switch (_role) {
        UserRole.vendedor => const VendedorHomeScreen(),
        UserRole.chofer => const ChoferHomeScreen(),
        UserRole.bodega => const BodegaHomeScreen(),
        UserRole.admin => const AdminHomeScreen(),
      };

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => destination),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Icon(
                      Icons.local_shipping_rounded,
                      size: 56,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppConstants.appName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Inicia sesión para continuar',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _usernameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Usuario',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => Validators.requiredNonEmpty(
                        v,
                        message: 'Ingresa tu usuario',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<UserRole>(
                      key: ValueKey(_role),
                      initialValue: _role,
                      decoration: const InputDecoration(
                        labelText: 'Rol',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      items: UserRole.values
                          .map(
                            (r) => DropdownMenuItem(
                              value: r,
                              child: Text(r.label),
                            ),
                          )
                          .toList(),
                      onChanged: _submitting
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _role = value);
                            },
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _submitting ? null : _onLogin,
                      child: _submitting
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : const Text('Ingresar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

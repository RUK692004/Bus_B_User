import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/brand.dart';
import 'sign_up_screen.dart';
import 'bus_search_screen.dart';

class LoginScreen extends StatefulWidget {
  final AuthService? authService;

  const LoginScreen({super.key, this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late final AuthService _authService = widget.authService ?? AuthService();

  bool _isLoading = false;
  String? _errorMessage;
  bool _isPasswordVisible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter email and password.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      await _authService.login(
        email: email,
        password: password,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const BusSearchScreen(),
        ),
      );
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[Login] Unexpected login error: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Welcome back\nto BusBee',
      subtitle: 'Log in to find buses and follow them live.',
      badgeText: 'Live bus tracking',
      badgeAction: 'Kochi',
      children: [
        if (_errorMessage != null) ...[
          InlineMessage(_errorMessage!),
          const SizedBox(height: 18),
        ],
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            hintText: 'Email',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passwordController,
          obscureText: !_isPasswordVisible,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _login(),
          decoration: InputDecoration(
            hintText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  _isPasswordVisible = !_isPasswordVisible;
                });
              },
              icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
        const SizedBox(height: 26),
        ElevatedButton(
          onPressed: _isLoading ? null : _login,
          child: _isLoading ? const ButtonSpinner() : const Text('Login'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isLoading
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SignUpScreen(),
                    ),
                  );
                },
          child: const Text("Don't have an account? Sign Up"),
        ),
      ],
    );
  }
}

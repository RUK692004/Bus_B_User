import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/brand.dart';
import 'login_screen.dart';

class SignUpScreen extends StatefulWidget {
  final AuthService? authService;

  const SignUpScreen({super.key, this.authService});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  late final AuthService _authService = widget.authService ?? AuthService();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (_isLoading) return;

    setState(() {
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() => _isLoading = true);

    try {
      await _authService.signUp(
        name: name,
        email: email,
        password: password,
      );

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[SignUp] Unexpected sign-up error: $e');
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
      title: 'Never miss\nyour bus again',
      subtitle: 'Create an account to search routes and track buses live.',
      badgeText: 'Free for riders',
      badgeAction: 'Join now',
      glow: GlowStyle.sweep,
      children: [
        if (_errorMessage != null) ...[
          InlineMessage(_errorMessage!),
          const SizedBox(height: 18),
        ],
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Enter your email';
                  }
                  if (!v.contains('@') || !v.contains('.')) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) {
                  if (v == null || v.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'Confirm Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) {
                  if (v != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        ElevatedButton(
          onPressed: _isLoading ? null : _signUp,
          child: _isLoading ? const ButtonSpinner() : const Text('Sign Up'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Already have an account? Login'),
        ),
      ],
    );
  }
}

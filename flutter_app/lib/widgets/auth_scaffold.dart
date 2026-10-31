import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'brand.dart';

/// Shared layout of the login and sign-up pages: soft gradient top, wordmark,
/// an accent banner, a big title and the form below.
class AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final String bannerText;
  final Color bannerColor;
  final List<Widget> children;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.bannerText,
    required this.children,
    this.bannerColor = AppColors.violet,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomCenter,
            stops: [0, 0.22, 0.45],
            colors: [Color(0xFFFFF4B8), Color(0xFFFBE3F6), AppColors.paper],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(alignment: Alignment.centerLeft, child: BrandWordmark()),
                const SizedBox(height: 28),
                AccentBanner(text: bannerText, color: bannerColor),
                const SizedBox(height: 32),
                Text(title, style: AppText.hero),
                const SizedBox(height: 10),
                Text(subtitle, style: AppText.secondary.copyWith(fontSize: 15)),
                const SizedBox(height: 28),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Spinner that fits inside a filled button.
class ButtonSpinner extends StatelessWidget {
  final Color color;

  const ButtonSpinner({super.key, this.color = AppColors.paper});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      width: 22,
      child: CircularProgressIndicator(color: color, strokeWidth: 2),
    );
  }
}

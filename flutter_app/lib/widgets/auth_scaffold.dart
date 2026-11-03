import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'brand.dart';

/// Shared layout of the login and sign-up pages: a glowing hero with the nav
/// bar, a badge, a big gradient headline, then the form in a dark panel.
class AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badgeText;
  final String? badgeAction;
  final GlowStyle glow;
  final List<Widget> children;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.children,
    this.badgeAction,
    this.glow = GlowStyle.top,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlowBackdrop(
        style: glow,
        intensity: 0.85,
        child: SizedBox.expand(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const NavBarPill(),
                  const SizedBox(height: 56),
                  Center(child: AnnouncementPill(badgeText, actionLabel: badgeAction)),
                  const SizedBox(height: 22),
                  GradientHeadline(title),
                  const SizedBox(height: 14),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: AppText.secondary.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 36),
                  GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Spinner that fits inside a silver button.
class ButtonSpinner extends StatelessWidget {
  final Color color;

  const ButtonSpinner({super.key, this.color = AppColors.onLight});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      width: 22,
      child: CircularProgressIndicator(color: color, strokeWidth: 2),
    );
  }
}

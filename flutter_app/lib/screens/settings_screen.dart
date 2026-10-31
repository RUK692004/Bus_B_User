import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  final AuthService? authService;

  const SettingsScreen({super.key, this.authService});

  Future<void> _logout(BuildContext context) async {
    final service = authService ?? AuthService();
    await service.logout();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'BusBee',
      applicationIcon: const BrandWordmark(size: 18),
      children: const [
        Text('Search buses by number or route and follow them live on their route timeline.'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: RoundIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                outlined: true,
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
            const SizedBox(height: 28),
            const Text('Settings', style: AppText.title),
            const SizedBox(height: 20),
            _SettingsRow(
              icon: Icons.info_outline,
              label: 'About BusBee',
              onTap: () => _showAbout(context),
            ),
            const Divider(),
            _SettingsRow(
              icon: Icons.description_outlined,
              label: 'Open-source licences',
              onTap: () => showLicensePage(context: context, applicationName: 'BusBee'),
            ),
            const Divider(),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Done for today?',
                              style: AppText.heading.copyWith(color: AppColors.paper, fontSize: 22),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'You can log back in any time.',
                              style: AppText.secondary.copyWith(color: AppColors.faint),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(color: AppColors.sun, shape: BoxShape.circle),
                        child: const Icon(Icons.waving_hand_outlined, color: AppColors.ink),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.paper,
                      foregroundColor: AppColors.ink,
                    ),
                    onPressed: () => _logout(context),
                    child: const Text('Logout'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 120),
            Center(
              child: Text.rich(
                TextSpan(
                  style: AppText.secondary,
                  children: [
                    const TextSpan(text: 'Made with '),
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(Icons.favorite, color: AppColors.danger, size: 16),
                    ),
                    TextSpan(
                      text: ' in Kochi',
                      style: AppText.secondary.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          children: [
            Icon(icon, color: AppColors.ink, size: 26),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: AppText.body.copyWith(fontSize: 17))),
          ],
        ),
      ),
    );
  }
}

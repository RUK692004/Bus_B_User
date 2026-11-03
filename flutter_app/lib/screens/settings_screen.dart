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
            NavBarPill(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RoundIconButton(
                    icon: Icons.arrow_back,
                    tooltip: 'Back',
                    size: 36,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 12),
                  const Text('Settings', style: AppText.heading),
                ],
              ),
              trailing: const Padding(
                padding: EdgeInsets.only(right: 9),
                child: BrandWordmark(size: 14),
              ),
            ),
            const SizedBox(height: 36),
            const GradientHeadline('Your BusBee', textAlign: TextAlign.start, style: AppText.title),
            const SizedBox(height: 16),
            GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
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
                ],
              ),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border, width: AppTheme.hairline),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: GlowBackdrop(
                  style: GlowStyle.bottom,
                  intensity: 0.9,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const GradientHeadline('Done for today?', style: AppText.title),
                        const SizedBox(height: 8),
                        Text(
                          'You can log back in any time.',
                          textAlign: TextAlign.center,
                          style: AppText.secondary.copyWith(color: AppColors.text.withValues(alpha: 0.75)),
                        ),
                        const SizedBox(height: 22),
                        ElevatedButton(
                          onPressed: () => _logout(context),
                          child: const Text('Logout'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 96),
            Center(
              child: Text.rich(
                TextSpan(
                  style: AppText.secondary.copyWith(color: AppColors.faint),
                  children: [
                    const TextSpan(text: 'Made with '),
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(Icons.favorite, color: AppColors.ember, size: 16),
                    ),
                    TextSpan(
                      text: ' in Kochi',
                      style: AppText.secondary.copyWith(color: AppColors.muted, fontWeight: FontWeight.w600),
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
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            Icon(icon, color: AppColors.muted, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: AppText.body.copyWith(fontSize: 16))),
            const Icon(Icons.chevron_right, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}

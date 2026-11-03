import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// "BusBee" wordmark: an ember ring followed by the name.
class BrandWordmark extends StatelessWidget {
  final double size;

  const BrandWordmark({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.ember, width: size * 0.22),
          ),
        ),
        SizedBox(width: size * 0.45),
        Text(
          'BusBee',
          style: AppText.heading.copyWith(fontSize: size * 1.05, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Where the ember glow sits behind a [GlowBackdrop].
enum GlowStyle {
  /// Pours down from the top edge.
  top,

  /// Thin lit rim of a dark planet rising at the bottom.
  horizon,

  /// Sweeps in from the bottom-right corner.
  sweep,

  /// Rises from the bottom centre.
  bottom,
}

/// Paints a soft ember glow behind [child] and sizes itself to the child.
///
/// Static on purpose: screen tests use `pumpAndSettle`, so a never-ending
/// animation here would hang them.
class GlowBackdrop extends StatelessWidget {
  final GlowStyle style;
  final Widget child;

  /// Scales the glow's brightness (0–1).
  final double intensity;

  const GlowBackdrop({
    super.key,
    required this.style,
    required this.child,
    this.intensity = 1,
  });

  @override
  Widget build(BuildContext context) {
    final glow = CustomPaint(painter: _GlowPainter(style, intensity), child: child);
    // The horizon's dark planet is left to spill below the box, so the glow
    // fades into the page instead of ending in a hard edge.
    return style == GlowStyle.horizon ? glow : ClipRect(child: glow);
  }
}

class _GlowPainter extends CustomPainter {
  final GlowStyle style;
  final double intensity;

  const _GlowPainter(this.style, this.intensity);

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case GlowStyle.top:
        _blob(canvas, Offset(size.width * 0.35, -size.width * 0.15), size.width * 1.05);
      case GlowStyle.sweep:
        _blob(canvas, Offset(size.width * 1.05, size.height * 1.02), size.width * 0.95);
      case GlowStyle.bottom:
        _blob(canvas, Offset(size.width / 2, size.height + size.width * 0.12), size.width * 0.85);
      case GlowStyle.horizon:
        _horizon(canvas, size);
    }
  }

  /// A radial glow: white-hot centre fading through ember to black.
  void _blob(Canvas canvas, Offset centre, double radius) {
    final rect = Rect.fromCircle(center: centre, radius: radius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.glow.withValues(alpha: intensity),
          AppColors.peach.withValues(alpha: 0.95 * intensity),
          AppColors.emberMid.withValues(alpha: 0.9 * intensity),
          AppColors.emberDeep.withValues(alpha: 0.6 * intensity),
          AppColors.background.withValues(alpha: 0),
        ],
        stops: const [0, 0.15, 0.35, 0.6, 1],
      ).createShader(rect);
    canvas.drawCircle(centre, radius, paint);
  }

  /// A huge dark circle whose top edge catches the light.
  void _horizon(Canvas canvas, Size size) {
    final radius = size.width * 1.1;
    final centre = Offset(size.width / 2, size.height - 48 + radius);

    // Only the rim is wanted: stop a little below the box, where the planet
    // has left the sides and everything under it is already black.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, size.height + 160));

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = AppColors.horizon.withValues(alpha: 0.85 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 38),
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = AppColors.glow.withValues(alpha: 0.9 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(
      centre.translate(0, 8),
      radius,
      Paint()
        ..color = AppColors.background
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlowPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.intensity != intensity;
}

/// Floating, hairline-bordered bar with the wordmark and a trailing action.
class NavBarPill extends StatelessWidget {
  final Widget? leading;
  final Widget? trailing;

  const NavBarPill({super.key, this.leading, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.only(left: 16, right: 7),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        border: Border.all(color: AppColors.borderStrong, width: AppTheme.hairline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          leading ?? const BrandWordmark(),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Small white button for the nav bar ("Login").
class NavBarButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const NavBarButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.text,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(label, style: AppText.label.copyWith(color: AppColors.onLight, fontSize: 13)),
        ),
      ),
    );
  }
}

/// Badge above a headline: "Live bus tracking | Kochi ›".
class AnnouncementPill extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onTap;

  const AnnouncementPill(this.text, {super.key, this.actionLabel, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.8),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border, width: AppTheme.hairline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, style: AppText.label.copyWith(color: AppColors.subtle, fontWeight: FontWeight.w500)),
              if (actionLabel != null) ...[
                Container(
                  width: AppTheme.hairline,
                  height: 12,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: AppColors.border,
                ),
                Text(actionLabel!, style: AppText.label.copyWith(color: AppColors.ember)),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right, size: 15, color: AppColors.ember),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Big light headline whose lines fade from grey (top) to white (bottom).
class GradientHeadline extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  const GradientHeadline(
    this.text, {
    super.key,
    this.style = AppText.hero,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.headlineTop, AppColors.text],
      ).createShader(bounds),
      child: Text(text, textAlign: textAlign, style: style),
    );
  }
}

/// Round dark icon button with a hairline border.
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  const RoundIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppColors.raised,
      shape: const CircleBorder(side: BorderSide(color: AppColors.border, width: AppTheme.hairline)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: AppColors.text, size: size * 0.44),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Small rounded label, e.g. "Bus No: KL-07-101" or "4 stops".
class Pill extends StatelessWidget {
  final String text;
  final IconData? icon;

  /// Ember text and tint instead of grey.
  final bool accent;

  const Pill(this.text, {super.key, this.icon, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppColors.ember : AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent ? AppColors.ember.withValues(alpha: 0.1) : AppColors.raised,
        border: Border.all(
          color: accent ? AppColors.ember.withValues(alpha: 0.4) : AppColors.border,
          width: AppTheme.hairline,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(text, style: AppText.label.copyWith(color: accent ? AppColors.ember : AppColors.text)),
        ],
      ),
    );
  }
}

/// Dark surface with a hairline border, used for cards and forms.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        border: Border.all(color: AppColors.border, width: AppTheme.hairline),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

/// Section title with an optional subtitle and trailing widget.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionHeader(this.title, {super.key, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.title),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: AppText.secondary),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Error or info message in the same hairline style as the rest of the page.
class InlineMessage extends StatelessWidget {
  final String text;
  final bool isError;

  const InlineMessage(this.text, {super.key, this.isError = true});

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.danger : AppColors.muted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.45), width: AppTheme.hairline),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.error_outline : Icons.info_outline, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppText.body.copyWith(color: color, fontSize: 14))),
        ],
      ),
    );
  }
}

/// Glowing green dot next to "live" text (grey when not live). Static, see
/// [GlowBackdrop].
class LiveDot extends StatelessWidget {
  final bool isLive;

  const LiveDot({super.key, required this.isLive});

  @override
  Widget build(BuildContext context) {
    final color = isLive ? AppColors.live : AppColors.faint;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          if (isLive) BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 1),
        ],
      ),
    );
  }
}

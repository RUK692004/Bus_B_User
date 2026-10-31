import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// "BusBee" wordmark.
class BrandWordmark extends StatelessWidget {
  final double size;

  const BrandWordmark({super.key, this.size = 26});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(size * 0.18),
          decoration: const BoxDecoration(color: AppColors.sun, shape: BoxShape.circle),
          child: Icon(Icons.directions_bus_rounded, size: size * 0.85, color: AppColors.ink),
        ),
        SizedBox(width: size * 0.3),
        Text(
          'BusBee',
          style: AppText.title.copyWith(fontSize: size, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

/// The small hand-drawn wave used to separate page sections.
class SquiggleDivider extends StatelessWidget {
  const SquiggleDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: CustomPaint(size: Size(84, 14), painter: _SquigglePainter()),
      ),
    );
  }
}

class _SquigglePainter extends CustomPainter {
  const _SquigglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(0, size.height / 2);
    for (double x = 0; x <= size.width; x += 1) {
      path.lineTo(x, size.height / 2 + sin(x / size.width * 3 * 2 * pi) * size.height / 3);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Black band with a repeated phrase, like a marquee frozen in place.
class TickerBand extends StatelessWidget {
  final String text;

  const TickerBand({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: AppColors.ink,
      alignment: Alignment.centerLeft,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: double.infinity,
          child: Text(
            List.filled(6, '  $text  ✨').join(),
            maxLines: 1,
            softWrap: false,
            style: AppText.body.copyWith(color: AppColors.paper, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// Round icon button: grey filled (default) or outlined.
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool outlined;
  final double size;

  const RoundIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.outlined = false,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: outlined ? AppColors.paper : AppColors.pill,
      shape: CircleBorder(
        side: outlined
            ? const BorderSide(color: AppColors.ink, width: AppTheme.outline)
            : BorderSide.none,
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: AppColors.ink, size: size * 0.44),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Grey rounded label, e.g. "KL-07-101" or "4 STOPS".
class Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;

  const Pill(this.text, {super.key, this.icon, this.color = AppColors.pill});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: AppColors.ink),
            const SizedBox(width: 6),
          ],
          Text(text, style: AppText.label),
        ],
      ),
    );
  }
}

/// A plain box with a thin black outline.
class OutlinedPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const OutlinedPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border.all(color: AppColors.ink, width: AppTheme.outline),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

/// One cell of a [TileGrid].
class GridTileItem {
  final String label;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const GridTileItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.iconColor = AppColors.ink,
  });
}

/// Two-column grid of outlined tiles ("Activities", "Study Jams", ...).
class TileGrid extends StatelessWidget {
  final List<GridTileItem> items;

  const TileGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    const side = BorderSide(color: AppColors.ink, width: AppTheme.outline);
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _tile(items[i], right: i + 1 < items.length)),
            if (i + 1 < items.length) Expanded(child: _tile(items[i + 1])),
          ],
        ),
      ));
      if (i + 2 < items.length) rows.add(const Divider(height: AppTheme.outline, thickness: AppTheme.outline, color: AppColors.ink));
    }
    return Container(
      decoration: const BoxDecoration(border: Border(left: side, right: side, bottom: side, top: side)),
      child: Column(children: rows),
    );
  }

  Widget _tile(GridTileItem item, {bool right = false}) {
    return Material(
      color: AppColors.paper,
      child: InkWell(
        onTap: item.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: right
              ? const BoxDecoration(
                  border: Border(right: BorderSide(color: AppColors.ink, width: AppTheme.outline)),
                )
              : null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: AppText.body.copyWith(
                    fontFamily: AppFonts.display,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Icon(item.icon, color: item.iconColor, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

/// Coloured strip with a short message and an underlined action
/// ("Claim your username   CLAIM NOW").
class AccentBanner extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color color;

  const AccentBanner({
    super.key,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.color = AppColors.violet,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: AppColors.ink, width: AppTheme.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: AppText.body.copyWith(color: AppColors.paper, fontSize: 16)),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: AppText.label.copyWith(
                  color: AppColors.paper,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.paper,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Error or info message in the same outlined style as the rest of the page.
class InlineMessage extends StatelessWidget {
  final String text;
  final bool isError;

  const InlineMessage(this.text, {super.key, this.isError = true});

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.danger : AppColors.ink;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color, width: AppTheme.outline),
        borderRadius: BorderRadius.circular(14),
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

/// Huge faded sign-off at the bottom of a page ("Hakuna Matata!").
class FadedFooter extends StatelessWidget {
  final String text;

  const FadedFooter({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppText.hero.copyWith(fontSize: 64, color: const Color(0xFFE9E9E9), height: 1),
          ),
          const SizedBox(height: 18),
          Text(
            '• • • •',
            style: AppText.secondary.copyWith(color: AppColors.faint, letterSpacing: 2),
          ),
          const SizedBox(height: 10),
          Text(
            'BusBee',
            style: AppText.heading.copyWith(color: AppColors.faint, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

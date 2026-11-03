import 'package:flutter/material.dart';

import '../models/bus_info.dart';
import '../theme/app_theme.dart';
import 'brand.dart';

/// A tappable summary of one bus in the search results: a dark hairline card
/// with the route name, its ends and small pills for the details.
class BusCard extends StatelessWidget {
  final BusInfo bus;
  final VoidCallback? onTap;

  const BusCard({super.key, required this.bus, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border, width: AppTheme.hairline),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.ember.withValues(alpha: 0.08),
          highlightColor: Colors.white.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(bus.name, style: AppText.heading.copyWith(fontSize: 20)),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        gradient: AppTheme.silverGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.north_east, size: 18, color: AppColors.onLight),
                    ),
                  ],
                ),
                if (bus.start != null && bus.end != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.route_outlined, size: 17, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${bus.start} → ${bus.end}',
                          style: AppText.secondary.copyWith(fontSize: 15, color: AppColors.text),
                        ),
                      ),
                    ],
                  ),
                ],
                if (bus.stops.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'via ${bus.stops.join(', ')}',
                    style: AppText.secondary.copyWith(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Pill('Bus No: ${bus.number}', icon: Icons.directions_bus_outlined),
                    if (bus.stops.isNotEmpty)
                      Pill('${bus.stops.length} ${bus.stops.length == 1 ? 'stop' : 'stops'}'),
                    // Only nearby results carry a distance; other searches report 0.
                    if (bus.distanceKm > 0)
                      Pill(
                        '${bus.distanceKm.toStringAsFixed(1)} km away',
                        icon: Icons.near_me_outlined,
                        accent: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

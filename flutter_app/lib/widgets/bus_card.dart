import 'package:flutter/material.dart';

import '../models/bus_info.dart';
import '../theme/app_theme.dart';
import 'brand.dart';

/// A tappable summary of one bus in the search results: an outlined card
/// with the route name, its ends and grey pills for the details.
class BusCard extends StatelessWidget {
  final BusInfo bus;
  final VoidCallback? onTap;

  const BusCard({super.key, required this.bus, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: AppColors.paper,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.ink, width: AppTheme.outline),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(bus.name, style: AppText.heading.copyWith(fontSize: 22)),
                    ),
                    const SizedBox(width: 12),
                    const RoundIconButton(icon: Icons.north_east, size: 40),
                  ],
                ),
                if (bus.start != null && bus.end != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.route_outlined, size: 18, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${bus.start} → ${bus.end}',
                          style: AppText.secondary.copyWith(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ],
                if (bus.stops.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'via ${bus.stops.join(', ')}',
                    style: AppText.secondary.copyWith(fontSize: 13, color: AppColors.faint),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Pill('Bus No: ${bus.number}', icon: Icons.directions_bus_outlined),
                    if (bus.stops.isNotEmpty)
                      Pill('${bus.stops.length} ${bus.stops.length == 1 ? 'STOP' : 'STOPS'}'),
                    // Only nearby results carry a distance; other searches report 0.
                    if (bus.distanceKm > 0)
                      Pill(
                        '${bus.distanceKm.toStringAsFixed(1)} km away',
                        icon: Icons.near_me_outlined,
                        color: AppColors.sun,
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

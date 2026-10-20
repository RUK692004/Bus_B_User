import 'package:flutter/material.dart';

import '../models/bus_info.dart';

/// A tappable summary of one bus in the search results.
class BusCard extends StatelessWidget {
  final BusInfo bus;
  final VoidCallback? onTap;

  const BusCard({super.key, required this.bus, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2C),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.directions_bus, color: Colors.white),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bus.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bus No: ${bus.number}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  if (bus.start != null && bus.end != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Route: ${bus.start} → ${bus.end}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                  if (bus.stops.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Stops: ${bus.stops.join(', ')}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Only nearby results carry a distance; other searches report 0.
                  if (bus.distanceKm > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${bus.distanceKm.toStringAsFixed(1)} km away',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }
}

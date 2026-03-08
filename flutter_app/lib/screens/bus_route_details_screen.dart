import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/bus_info.dart';

class BusRouteDetailsScreen extends StatelessWidget {
  final BusInfo bus;

  const BusRouteDetailsScreen({super.key, required this.bus});

  List<String> _buildRoutePoints() {
    final points = <String>[];

    if (bus.start != null && bus.start!.trim().isNotEmpty) {
      points.add(bus.start!.trim());
    }

    for (final stop in bus.stops) {
      if (stop.trim().isNotEmpty) {
        points.add(stop.trim());
      }
    }

    if (bus.end != null && bus.end!.trim().isNotEmpty) {
      points.add(bus.end!.trim());
    }

    return points;
  }

  Future<void> _openInGoogleMaps(
    BuildContext context,
    List<String> routePoints,
  ) async {
    if (routePoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Route information is incomplete for this bus.'),
        ),
      );
      return;
    }

    final origin = routePoints.first;
    final destination = routePoints.last;
    final waypoints = routePoints.length > 2
        ? routePoints.sublist(1, routePoints.length - 1).join('|')
        : null;

    final uri = Uri.https(
      'www.google.com',
      '/maps/dir/',
      <String, String>{
        'api': '1',
        'origin': origin,
        'destination': destination,
        if (waypoints != null && waypoints.isNotEmpty) 'waypoints': waypoints,
        'travelmode': 'driving',
      },
    );

    final canLaunch = await canLaunchUrl(uri);
    if (!canLaunch) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Google Maps.'),
          ),
        );
      }
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = _buildRoutePoints();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bus.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'Bus No: ${bus.number}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Route stops',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: routePoints.length,
              itemBuilder: (context, index) {
                final point = routePoints[index];
                final isFirst = index == 0;
                final isLast = index == routePoints.length - 1;

                String label;
                if (isFirst) {
                  label = 'Start';
                } else if (isLast) {
                  label = 'Destination';
                } else {
                  label = 'Stop $index';
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isFirst
                            ? Icons.trip_origin
                            : isLast
                                ? Icons.flag
                                : Icons.stop_circle,
                        color: isFirst || isLast
                            ? Colors.blueAccent
                            : Colors.white60,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              point,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => _openInGoogleMaps(context, routePoints),
                  icon: const Icon(Icons.map, color: Colors.white),
                  label: const Text(
                    'Open in Google Maps',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


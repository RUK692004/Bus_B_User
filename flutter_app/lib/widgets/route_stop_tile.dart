import 'package:flutter/material.dart';

/// One row in a bus's list of route stops.
class RouteStopTile extends StatelessWidget {
  final String name;

  /// Position in the route (0 = start).
  final int index;
  final int totalStops;

  const RouteStopTile({
    super.key,
    required this.name,
    required this.index,
    required this.totalStops,
  });

  bool get _isFirst => index == 0;
  bool get _isLast => index == totalStops - 1;

  @override
  Widget build(BuildContext context) {
    final label = _isFirst
        ? 'Start'
        : _isLast
            ? 'Destination'
            : 'Stop $index';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _isFirst
                ? Icons.trip_origin
                : _isLast
                    ? Icons.flag
                    : Icons.stop_circle,
            color: _isFirst || _isLast ? Colors.blueAccent : Colors.white60,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
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
  }
}

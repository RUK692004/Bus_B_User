import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Where a bus is along its route, for the stop timeline.
///
/// The bus is between stop [fromIndex] and stop [toIndex], [fraction] of the
/// way (0 = at `fromIndex`, 1 = at `toIndex`).
class RouteProgress {
  final int fromIndex;
  final double fraction;

  /// Distance travelled along the route from the first stop, in metres.
  final double distanceAlongMetres;

  /// Straight-line distance from the bus to the route, in metres.
  final double offRouteMetres;

  /// The stop the bus is currently at (within [RouteProgressTracker.atStopRadiusMetres]), if any.
  final int? atStopIndex;

  const RouteProgress({
    required this.fromIndex,
    required this.fraction,
    required this.distanceAlongMetres,
    required this.offRouteMetres,
    this.atStopIndex,
  });

  int get toIndex => fromIndex + 1;

  @override
  String toString() =>
      'RouteProgress(from: $fromIndex, fraction: ${fraction.toStringAsFixed(2)}, '
      'along: ${distanceAlongMetres.round()} m, off: ${offRouteMetres.round()} m, at: $atStopIndex)';
}

/// Turns live bus positions into [RouteProgress] for an ordered list of stops.
///
/// The bus is snapped to the nearest point on the line through the stops; its
/// distance along that line decides which two stops it is between. Small
/// backwards moves (GPS jitter) are ignored so the bus never jumps back.
class RouteProgressTracker {
  final List<LatLng> stops;

  /// Backwards moves shorter than this keep the previous progress.
  final double jitterMetres;

  /// A bus this close (along the route) to a stop counts as "at" that stop.
  final double atStopRadiusMetres;

  late final List<double> _stopDistances = _cumulativeDistances(stops);
  RouteProgress? _last;

  RouteProgressTracker(
    this.stops, {
    this.jitterMetres = 50,
    this.atStopRadiusMetres = 100,
  }) : assert(stops.length >= 2, 'A route needs at least two stops.');

  /// Distance of each stop from the first stop along the route, in metres.
  List<double> get stopDistances => _stopDistances;

  /// The latest progress, or null before the first [update].
  RouteProgress? get current => _last;

  RouteProgress update(LatLng bus) {
    final next = _project(bus);
    final last = _last;
    if (last != null &&
        next.distanceAlongMetres < last.distanceAlongMetres &&
        last.distanceAlongMetres - next.distanceAlongMetres < jitterMetres) {
      return last;
    }
    return _last = next;
  }

  RouteProgress _project(LatLng bus) {
    var bestDistance = double.infinity;
    var bestSegment = 0;
    var bestT = 0.0;

    for (var i = 0; i < stops.length - 1; i++) {
      // Local flat-earth coordinates in metres, centred on the bus. Accurate
      // enough over the few kilometres between two bus stops.
      final a = _toMetres(stops[i], bus);
      final b = _toMetres(stops[i + 1], bus);
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final lengthSquared = dx * dx + dy * dy;
      final t = lengthSquared == 0
          ? 0.0
          : ((-a.x) * dx + (-a.y) * dy) / lengthSquared;
      final clamped = t.clamp(0.0, 1.0);
      final px = a.x + clamped * dx;
      final py = a.y + clamped * dy;
      final distance = sqrt(px * px + py * py);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestSegment = i;
        bestT = clamped;
      }
    }

    final segmentLength = _stopDistances[bestSegment + 1] - _stopDistances[bestSegment];
    final along = _stopDistances[bestSegment] + bestT * segmentLength;

    int? atStop;
    for (var k = 0; k < stops.length; k++) {
      if ((along - _stopDistances[k]).abs() <= atStopRadiusMetres) {
        atStop = k;
        break;
      }
    }

    return RouteProgress(
      fromIndex: bestSegment,
      fraction: bestT,
      distanceAlongMetres: along,
      offRouteMetres: bestDistance,
      atStopIndex: atStop,
    );
  }

  static List<double> _cumulativeDistances(List<LatLng> points) {
    final distances = <double>[0];
    for (var i = 1; i < points.length; i++) {
      distances.add(distances.last + distanceMetres(points[i - 1], points[i]));
    }
    return distances;
  }

  static Point<double> _toMetres(LatLng p, LatLng origin) {
    const metresPerDegreeLat = 110540.0;
    final metresPerDegreeLng = 111320.0 * cos(origin.latitude * pi / 180);
    return Point(
      (p.longitude - origin.longitude) * metresPerDegreeLng,
      (p.latitude - origin.latitude) * metresPerDegreeLat,
    );
  }
}

/// Great-circle (haversine) distance between two points, in metres.
double distanceMetres(LatLng a, LatLng b) {
  const earthRadius = 6371000.0;
  final dLat = (b.latitude - a.latitude) * pi / 180;
  final dLng = (b.longitude - a.longitude) * pi / 180;
  final h = sin(dLat / 2) * sin(dLat / 2) +
      cos(a.latitude * pi / 180) * cos(b.latitude * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
  return earthRadius * 2 * atan2(sqrt(h), sqrt(1 - h));
}

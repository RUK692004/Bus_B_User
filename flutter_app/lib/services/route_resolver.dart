import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/bus_info.dart';
import 'bus_service.dart';

enum RouteStopKind { start, stop, end }

/// One point of a bus route that has a position on the map.
class RouteStop {
  final String name;
  final LatLng position;
  final RouteStopKind kind;

  /// Position of the stop in the route (0 = start).
  final int index;

  const RouteStop({
    required this.name,
    required this.position,
    required this.kind,
    required this.index,
  });

  String get label => switch (kind) {
        RouteStopKind.start => 'Start',
        RouteStopKind.end => 'Destination',
        RouteStopKind.stop => 'Stop $index',
      };
}

/// A route ready to draw, plus a warning to show when it is incomplete.
class ResolvedRoute {
  final List<RouteStop> stops;
  final String? warning;

  const ResolvedRoute({required this.stops, this.warning});

  List<LatLng> get points => [for (final stop in stops) stop.position];
}

/// Looks up the map coordinates of a bus route.
///
/// Uses the coordinates saved on the server (`/api/buses/:id/route`) when
/// there are at least two; otherwise geocodes the stop names.
class RouteResolver {
  final BusService busService;
  final Future<List<Location>> Function(String address) _geocode;

  /// Upper bound on geocoded stops. Geocoding is slow on mobile and an
  /// unbounded loop can trigger an ANR.
  final int maxGeocodedStops;

  RouteResolver({
    required this.busService,
    Future<List<Location>> Function(String address)? geocode,
    int? maxGeocodedStops,
  })  : _geocode = geocode ?? locationFromAddress,
        maxGeocodedStops = maxGeocodedStops ?? (kIsWeb ? 1 << 30 : 8);

  Future<ResolvedRoute> resolve(BusInfo bus) async {
    final names = bus.routeStopNames;
    if (names.length < 2) {
      return const ResolvedRoute(
        stops: [],
        warning: 'Not enough route data to render the map.',
      );
    }

    final saved = await _savedRoute(bus, names);
    if (saved.length >= 2) {
      return ResolvedRoute(stops: saved);
    }

    final geocoded = await _geocodedRoute(bus, names);
    String? warning;
    if (geocoded.length < 2) {
      warning = 'Could not resolve full route on map.';
    } else if (names.length > maxGeocodedStops) {
      warning = 'Route has many stops. Add route coordinates for this bus on the server for faster map loading.';
    }
    return ResolvedRoute(stops: geocoded, warning: warning);
  }

  Future<List<RouteStop>> _savedRoute(BusInfo bus, List<String> names) async {
    final busId = bus.id;
    if (busId == null || busId.isEmpty) return const [];

    final List<Map<String, dynamic>> entries;
    try {
      entries = await busService.getBusRoute(busId);
    } catch (e) {
      debugPrint('[RouteResolver] Saved route unavailable for bus $busId, falling back to geocoding: $e');
      return const [];
    }

    final stops = <RouteStop>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final lat = _asDouble(entry['lat']);
      final lng = _asDouble(entry['lng']);
      if (lat == null || lng == null) continue;

      final savedName = (entry['name'] as String?)?.trim() ?? '';
      final kind = switch ((entry['kind'] as String?)?.toLowerCase()) {
        'start' => RouteStopKind.start,
        'end' => RouteStopKind.end,
        _ when i == 0 => RouteStopKind.start,
        _ when i == entries.length - 1 => RouteStopKind.end,
        _ => RouteStopKind.stop,
      };

      stops.add(RouteStop(
        name: savedName.isNotEmpty ? savedName : (i < names.length ? names[i] : 'Stop'),
        position: LatLng(lat, lng),
        kind: kind,
        index: i,
      ));
    }
    return stops;
  }

  Future<List<RouteStop>> _geocodedRoute(BusInfo bus, List<String> names) async {
    final stops = <RouteStop>[];
    for (var i = 0; i < names.length && i < maxGeocodedStops; i++) {
      final position = await _geocodePlace(names[i], bus);
      if (position == null) continue;

      stops.add(RouteStop(
        name: names[i],
        position: position,
        kind: i == 0
            ? RouteStopKind.start
            : i == names.length - 1
                ? RouteStopKind.end
                : RouteStopKind.stop,
        index: i,
      ));
    }
    return stops;
  }

  Future<LatLng?> _geocodePlace(String place, BusInfo bus) async {
    // Try several query formats to improve the match rate.
    final startHint = (bus.start ?? '').trim();
    final endHint = (bus.end ?? '').trim();
    final queries = <String>{
      place,
      if (startHint.isNotEmpty) '$place, $startHint',
      if (endHint.isNotEmpty) '$place, $endHint',
      '$place, Kochi, Kerala, India',
      '$place, Kerala, India',
      '$place, India',
    };

    for (final query in queries) {
      try {
        final locations = await _geocode(query).timeout(const Duration(seconds: 3));
        if (locations.isNotEmpty) {
          return LatLng(locations.first.latitude, locations.first.longitude);
        }
      } catch (_) {
        // No match for this variant (or a timeout); try the next one.
      }
    }
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

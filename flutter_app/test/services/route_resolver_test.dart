import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_app/models/bus_info.dart';
import 'package:flutter_app/services/api_client.dart';
import 'package:flutter_app/services/bus_service.dart';
import 'package:flutter_app/services/route_resolver.dart';

BusService _busServiceReturningRoute(List<Map<String, dynamic>>? route) {
  final client = MockClient((request) async {
    if (route == null) return http.Response(jsonEncode({'message': 'boom'}), 500);
    return http.Response(jsonEncode({'route': route}), 200);
  });
  return BusService(apiClient: ApiClient(baseUrl: 'http://localhost:5000', client: client));
}

Location _location(double lat, double lng) =>
    Location(latitude: lat, longitude: lng, timestamp: DateTime(2026));

const _bus = BusInfo(
  id: 'bus-1',
  name: 'Test Bus',
  number: '1',
  distanceKm: 0,
  start: 'Aluva',
  end: 'Vyttila',
  stops: ['Kaloor'],
);

void main() {
  group('RouteResolver', () {
    test('uses saved coordinates from the server when there are at least two', () async {
      final geocoded = <String>[];
      final resolver = RouteResolver(
        busService: _busServiceReturningRoute([
          {'seq': 0, 'name': 'Aluva', 'lat': 10.1, 'lng': 76.3},
          {'seq': 1, 'name': '', 'lat': '10.0', 'lng': '76.29'},
          {'seq': 2, 'name': 'Vyttila', 'lat': 9.96, 'lng': 76.32},
        ]),
        geocode: (address) async {
          geocoded.add(address);
          return const [];
        },
      );

      final route = await resolver.resolve(_bus);

      expect(geocoded, isEmpty);
      expect(route.warning, isNull);
      expect(route.points, const [LatLng(10.1, 76.3), LatLng(10.0, 76.29), LatLng(9.96, 76.32)]);
      expect(route.stops.map((s) => s.kind), [RouteStopKind.start, RouteStopKind.stop, RouteStopKind.end]);
      // A blank saved name falls back to the stop name at that position.
      expect(route.stops[1].name, 'Kaloor');
      expect(route.stops.map((s) => s.label), ['Start', 'Stop 1', 'Destination']);
    });

    test('falls back to geocoding stop names when the saved route is unavailable', () async {
      final resolver = RouteResolver(
        busService: _busServiceReturningRoute(null),
        geocode: (address) async => switch (address) {
          'Aluva' => [_location(10.1, 76.3)],
          'Kaloor' => [_location(10.0, 76.29)],
          'Vyttila' => [_location(9.96, 76.32)],
          _ => const [],
        },
      );

      final route = await resolver.resolve(_bus);

      expect(route.warning, isNull);
      expect(route.stops.map((s) => s.name), ['Aluva', 'Kaloor', 'Vyttila']);
      expect(route.stops.map((s) => s.kind), [RouteStopKind.start, RouteStopKind.stop, RouteStopKind.end]);
    });

    test('tries place-name variants with hints until one matches', () async {
      final tried = <String>[];
      final resolver = RouteResolver(
        busService: _busServiceReturningRoute(const []),
        geocode: (address) async {
          tried.add(address);
          if (address == 'Kaloor, Kochi, Kerala, India') return [_location(10.0, 76.29)];
          if (address == 'Aluva' || address == 'Vyttila') return [_location(10.0, 76.0)];
          return const [];
        },
      );

      final route = await resolver.resolve(_bus);

      expect(route.stops.map((s) => s.name), ['Aluva', 'Kaloor', 'Vyttila']);
      expect(
        tried.where((a) => a.startsWith('Kaloor')),
        ['Kaloor', 'Kaloor, Aluva', 'Kaloor, Vyttila', 'Kaloor, Kochi, Kerala, India'],
      );
    });

    test('warns when fewer than two stops can be placed on the map', () async {
      final resolver = RouteResolver(
        busService: _busServiceReturningRoute(const []),
        geocode: (address) async => address == 'Aluva' ? [_location(10.1, 76.3)] : const [],
      );

      final route = await resolver.resolve(_bus);

      expect(route.stops, hasLength(1));
      expect(route.warning, 'Could not resolve full route on map.');
    });

    test('limits geocoding to maxGeocodedStops and warns about it', () async {
      final resolver = RouteResolver(
        busService: _busServiceReturningRoute(const []),
        maxGeocodedStops: 2,
        geocode: (address) async => [_location(1, 1)],
      );

      final route = await resolver.resolve(_bus);

      expect(route.stops.map((s) => s.name), ['Aluva', 'Kaloor']);
      expect(route.warning, contains('Route has many stops'));
    });

    test('reports missing route data without calling the server', () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      final resolver = RouteResolver(
        busService: BusService(apiClient: ApiClient(baseUrl: 'http://localhost:5000', client: client)),
      );

      final route = await resolver.resolve(
        const BusInfo(id: 'bus-2', name: 'x', number: '2', distanceKm: 0, start: 'Only stop'),
      );

      expect(requests, 0);
      expect(route.stops, isEmpty);
      expect(route.warning, 'Not enough route data to render the map.');
    });
  });
}

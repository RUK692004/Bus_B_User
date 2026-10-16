import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_app/services/api_client.dart';
import 'package:flutter_app/services/bus_service.dart';
import '../test_helpers.dart';

void main() {
  group('BusService', () {
    test('getNearbyBuses queries endpoint with coordinates and parses response', () async {
      final mockHttp = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/buses/nearby');
        expect(request.url.queryParameters['lat'], '12.9716');
        expect(request.url.queryParameters['lng'], '77.5946');
        expect(request.url.queryParameters['radius'], '2000.0');

        return http.Response(
          jsonEncode({
            'buses': [
              {
                'id': 'bus-1',
                'bus_number': '101A',
                'bus_name': 'Downtown Express',
                'start_location': 'Central Hub',
                'end_location': 'Tech Park',
                'stops': ['Stop 1', 'Stop 2'],
                'lat': 12.972,
                'lng': 77.595,
                'distance_km': 0.45,
              }
            ]
          }),
          200,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final busService = BusService(apiClient: apiClient);

      final buses = await busService.getNearbyBuses(
        lat: 12.9716,
        lng: 77.5946,
        radiusMeters: 2000.0,
      );

      expect(buses.length, 1);
      expect(buses.first.id, 'bus-1');
      expect(buses.first.number, '101A');
      expect(buses.first.name, 'Downtown Express');
      expect(buses.first.distanceKm, 0.45);
      expect(buses.first.stops, ['Stop 1', 'Stop 2']);
      expect(buses.first.lat, 12.972);
      expect(buses.first.lng, 77.595);
    });

    test('getNearbyBuses falls back seamlessly to /api/v1/buses if /api/buses returns 404 Route not found', () async {
      final mockHttp = MockClient((request) async {
        if (request.url.path == '/api/buses/nearby') {
          return http.Response(jsonEncode({'message': 'Route not found.'}), 404);
        }
        if (request.url.path == '/api/v1/buses/nearby') {
          return http.Response(
            jsonEncode({
              'buses': [
                {
                  'id': 'v1-bus',
                  'bus_number': 'V1-99',
                  'bus_name': 'V1 Special',
                  'distance_km': 1.1,
                }
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final busService = BusService(apiClient: apiClient);

      final buses = await busService.getNearbyBuses(lat: 10.0, lng: 20.0);
      expect(buses.length, 1);
      expect(buses.first.number, 'V1-99');
    });

    test('searchBusByNumber returns BusInfo on 200', () async {
      final mockHttp = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/buses/search');
        expect(request.url.queryParameters['number'], '500K');

        return http.Response(
          jsonEncode({
            'bus': {
              'id': 'bus-500k',
              'bus_number': '500K',
              'bus_name': 'Outer Ring Express',
              'start_location': 'Silk Board',
              'end_location': 'Hebbal',
              'stops': ['Marathahalli', 'Tin Factory'],
            }
          }),
          200,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final busService = BusService(apiClient: apiClient);

      final bus = await busService.searchBusByNumber('500K');
      expect(bus, isNotNull);
      expect(bus!.id, 'bus-500k');
      expect(bus.number, '500K');
      expect(bus.name, 'Outer Ring Express');
      expect(bus.start, 'Silk Board');
      expect(bus.end, 'Hebbal');
      expect(bus.stops, ['Marathahalli', 'Tin Factory']);
    });

    test('searchBusByNumber returns null on 404 Bus not found', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(jsonEncode({'message': 'Bus not found.'}), 404);
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final busService = BusService(apiClient: apiClient);

      final bus = await busService.searchBusByNumber('NONEXISTENT');
      expect(bus, isNull);
    });

    test('searchTrips returns matching buses between from and to', () async {
      final mockHttp = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/buses/trips');
        expect(request.url.queryParameters['from'], 'Majestic');
        expect(request.url.queryParameters['to'], 'Whitefield');

        return http.Response(
          jsonEncode({
            'buses': [
              {
                'id': 'trip-bus-1',
                'bus_number': '335E',
                'bus_name': 'ITPL Line',
                'start_location': 'Majestic',
                'end_location': 'Kadugodi',
                'stops': ['Domlur', 'Whitefield', 'Hope Farm'],
              }
            ]
          }),
          200,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final busService = BusService(apiClient: apiClient);

      final trips = await busService.searchTrips(from: 'Majestic', to: 'Whitefield');
      expect(trips.length, 1);
      expect(trips.first.number, '335E');
      expect(trips.first.start, 'Majestic');
      expect(trips.first.stops, contains('Whitefield'));
    });

    test('getBusRoute fetches route coordinates for a bus', () async {
      final mockHttp = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/buses/bus-101/route');

        return http.Response(
          jsonEncode({
            'route': [
              {
                'id': 1,
                'bus_id': 'bus-101',
                'seq': 1,
                'name': 'Origin Stop',
                'lat': 12.9716,
                'lng': 77.5946,
              },
              {
                'id': 2,
                'bus_id': 'bus-101',
                'seq': 2,
                'name': 'Destination Stop',
                'lat': 12.9800,
                'lng': 77.6000,
              },
            ]
          }),
          200,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final busService = BusService(apiClient: apiClient);

      final route = await busService.getBusRoute('bus-101');
      expect(route.length, 2);
      expect(route[0]['name'], 'Origin Stop');
      expect(route[0]['lat'], 12.9716);
      expect(route[1]['name'], 'Destination Stop');
      expect(route[1]['lng'], 77.6000);
    });

    test('subscribeBusLocation connects, subscribes, emits location updates, and unsubscribes on cancel', () async {
      final fakeChannel = FakeWebSocketChannel();
      final busService = BusService();

      final stream = busService.subscribeBusLocation(
        busId: 'bus-42',
        channel: fakeChannel,
      );

      final List<Map<String, dynamic>> receivedLocations = [];
      final sub = stream.listen(receivedLocations.add);

      // Verify that the subscription message was sent to the sink
      final sentMessages = <Map<String, dynamic>>[];
      fakeChannel.outgoing.stream.listen((data) {
        sentMessages.add(jsonDecode(data.toString()));
      });

      await Future.delayed(const Duration(milliseconds: 10));
      expect(sentMessages.length, 1);
      expect(sentMessages.first['type'], 'subscribe');
      expect(sentMessages.first['busId'], 'bus-42');

      // Server sends connected greeting and subscribed message (should be ignored by stream)
      fakeChannel.incoming.add(jsonEncode({'type': 'connected', 'message': 'Welcome'}));
      fakeChannel.incoming.add(jsonEncode({'type': 'subscribed', 'busId': 'bus-42'}));

      // Server sends location update
      fakeChannel.incoming.add(jsonEncode({
        'type': 'location_update',
        'busId': 'bus-42',
        'lat': 12.9500,
        'lng': 77.5800,
        'heading': 180,
      }));

      await Future.delayed(const Duration(milliseconds: 10));
      expect(receivedLocations.length, 1);
      expect(receivedLocations.first['lat'], 12.9500);
      expect(receivedLocations.first['lng'], 77.5800);
      expect(receivedLocations.first['heading'], 180);

      // Cancel stream subscription -> sends unsubscribe message
      await sub.cancel();
      await Future.delayed(const Duration(milliseconds: 10));

      expect(sentMessages.any((msg) => msg['type'] == 'unsubscribe' && msg['busId'] == 'bus-42'), true);
    });
  });
}

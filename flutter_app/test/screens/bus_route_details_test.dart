import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_app/models/bus_info.dart';
import 'package:flutter_app/screens/bus_route_details_screen.dart';
import 'package:flutter_app/services/api_client.dart';
import 'package:flutter_app/services/bus_service.dart';
import '../test_helpers.dart';

void main() {
  group('BusRouteDetailsScreen Widget Tests', () {
    testWidgets('loads route points from backend and connects to WebSocket', (tester) async {
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/route')) {
          return http.Response(
            jsonEncode({
              'route': [
                {
                  'id': 1,
                  'bus_id': 'bus-test-1',
                  'seq': 1,
                  'name': 'Terminal A',
                  'lat': 12.9716,
                  'lng': 77.5946,
                },
                {
                  'id': 2,
                  'bus_id': 'bus-test-1',
                  'seq': 2,
                  'name': 'Terminal B',
                  'lat': 12.9800,
                  'lng': 77.6000,
                },
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final fakeChannel = FakeWebSocketChannel();
      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final busService = BusService(apiClient: apiClient);

      const bus = BusInfo(
        id: 'bus-test-1',
        name: 'Route 101 Express',
        number: '101',
        distanceKm: 2.5,
        start: 'Terminal A',
        end: 'Terminal B',
        stops: ['Stop 1', 'Stop 2'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusRouteDetailsScreen(
            bus: bus,
            busService: busService,
            wsChannel: fakeChannel,
          ),
        ),
      );

      // Verify title bar
      expect(find.text('Route 101 Express'), findsOneWidget);
      expect(find.text('Live route - 101'), findsOneWidget);
      expect(find.text('Go to Google Maps'), findsOneWidget);

      // Let the saved route load: the timeline shows its stops, with no bus yet.
      await tester.pump();
      await tester.pump();
      expect(find.text('Terminal A'), findsOneWidget);
      expect(find.text('Terminal B'), findsOneWidget);
      expect(find.text('Waiting for live location…'), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline_bus_icon')), findsNothing);

      // Verify subscription message sent via WebSocket
      final sentMessages = <Map<String, dynamic>>[];
      fakeChannel.outgoing.stream.listen((data) {
        sentMessages.add(jsonDecode(data.toString()));
      });

      await tester.pump(const Duration(milliseconds: 50));

      expect(sentMessages.any((msg) => msg['type'] == 'subscribe' && msg['busId'] == 'bus-test-1'), true);

      // Send live location update via WebSocket
      fakeChannel.incoming.add(jsonEncode({
        'type': 'location_update',
        'busId': 'bus-test-1',
        'lat': 12.9750,
        'lng': 77.5970,
        'heading': 90,
      }));

      await tester.pump(const Duration(milliseconds: 50));

      // The bus is placed on the timeline between the two stops.
      expect(find.text('Between Terminal A and Terminal B'), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline_bus_icon')), findsOneWidget);
      expect(find.textContaining('Live · updated'), findsOneWidget);
      expect(find.text('Terminal B'), findsOneWidget);
      expect(find.text('Destination · Next stop'), findsOneWidget);

      // Leave screen to verify disposal
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Done'))));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Done'), findsOneWidget);
    });
  });
}

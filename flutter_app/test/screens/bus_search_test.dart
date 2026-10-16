import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_app/screens/bus_route_details_screen.dart';
import 'package:flutter_app/screens/bus_search_screen.dart';
import 'package:flutter_app/services/api_client.dart';
import 'package:flutter_app/services/bus_service.dart';

void main() {
  group('BusSearchScreen Widget Tests', () {
    testWidgets('search trips validates empty fields', (tester) async {
      final busService = BusService();

      await tester.pumpWidget(
        MaterialApp(
          home: BusSearchScreen(busService: busService),
        ),
      );

      // Tap 'Search Trips' button without input
      await tester.tap(find.widgetWithText(ElevatedButton, 'Search Trips'));
      await tester.pump();

      expect(
        find.text('Please enter both starting point and destination.'),
        findsOneWidget,
      );
    });

    testWidgets('search trips validates same origin and destination', (tester) async {
      final busService = BusService();

      await tester.pumpWidget(
        MaterialApp(
          home: BusSearchScreen(busService: busService),
        ),
      );

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'City Center');
      await tester.enterText(textFields.at(1), 'City Center');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Search Trips'));
      await tester.pump();

      expect(
        find.text('Starting point and destination cannot be the same.'),
        findsOneWidget,
      );
    });

    testWidgets('search trips displays returned buses on success', (tester) async {
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/trips')) {
          return http.Response(
            jsonEncode({
              'buses': [
                {
                  'id': 'bus-101',
                  'bus_number': '101',
                  'bus_name': 'Express Route 101',
                  'start_location': 'Station A',
                  'end_location': 'Station B',
                  'stops': ['Stop 1', 'Stop 2'],
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

      await tester.pumpWidget(
        MaterialApp(
          home: BusSearchScreen(busService: busService),
        ),
      );

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Station A');
      await tester.enterText(textFields.at(1), 'Station B');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Search Trips'));
      await tester.pumpAndSettle();

      expect(find.text('Express Route 101'), findsOneWidget);
      expect(find.text('Bus No: 101'), findsOneWidget);
    });

    testWidgets('search trips shows message when no buses found', (tester) async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({'buses': []}),
          200,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final busService = BusService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: BusSearchScreen(busService: busService),
        ),
      );

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Remote Village A');
      await tester.enterText(textFields.at(1), 'Remote Village B');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Search Trips'));
      await tester.pumpAndSettle();

      expect(find.text('No buses found for this route.'), findsOneWidget);
    });

    testWidgets('search by bus number shows result and navigates on tap', (tester) async {
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/search')) {
          expect(request.url.queryParameters['number'], '202');
          return http.Response(
            jsonEncode({
              'bus': {
                'id': 'bus-202',
                'bus_number': '202',
                'bus_name': 'Airport Flyer',
                'start_location': 'City',
                'end_location': 'Airport',
                'stops': ['Terminal 1', 'Terminal 2'],
              }
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final busService = BusService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: BusSearchScreen(busService: busService),
        ),
      );

      // Bus search input is the 3rd TextField
      final busSearchInput = find.widgetWithText(TextField, 'Search by Bus No.');
      await tester.enterText(busSearchInput, '202');

      // Tap search arrow icon button
      final searchArrow = find.byIcon(Icons.arrow_forward_ios);
      await tester.tap(searchArrow);
      await tester.pumpAndSettle();

      expect(find.text('Airport Flyer'), findsOneWidget);
      expect(find.text('Bus No: 202'), findsOneWidget);

      // Tap the bus card to verify navigation to route details
      await tester.tap(find.text('Airport Flyer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(BusRouteDetailsScreen), findsOneWidget);
    });

    testWidgets('search by bus number displays error when not found', (tester) async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Bus not found.'}),
          404,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final busService = BusService(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: BusSearchScreen(busService: busService),
        ),
      );

      final busSearchInput = find.widgetWithText(TextField, 'Search by Bus No.');
      await tester.enterText(busSearchInput, '9999');

      await tester.tap(find.byIcon(Icons.arrow_forward_ios));
      await tester.pumpAndSettle();

      expect(find.text('No bus found with that number.'), findsOneWidget);
    });
  });
}

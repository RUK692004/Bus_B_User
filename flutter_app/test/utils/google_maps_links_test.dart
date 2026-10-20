import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flutter_app/utils/google_maps_links.dart';

void main() {
  group('googleMapsDirectionsUri', () {
    test('routes from the first stop to the last, with the rest as waypoints', () {
      final uri = googleMapsDirectionsUri(stopNames: ['Aluva', 'Kaloor', 'MG Road', 'Vyttila'])!;

      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters, {
        'api': '1',
        'origin': 'Aluva',
        'destination': 'Vyttila',
        'waypoints': 'Kaloor|MG Road',
        'travelmode': 'driving',
      });
    });

    test('omits waypoints for a two-stop route', () {
      final uri = googleMapsDirectionsUri(stopNames: ['Aluva', 'Vyttila'])!;

      expect(uri.queryParameters.containsKey('waypoints'), isFalse);
    });

    test('starts from the live bus position when it is known', () {
      final uri = googleMapsDirectionsUri(
        stopNames: ['Aluva', 'Kaloor', 'Vyttila'],
        busPosition: const LatLng(10.05, 76.31),
      )!;

      expect(uri.queryParameters['origin'], '10.05,76.31');
      expect(uri.queryParameters['destination'], 'Vyttila');
      expect(uri.queryParameters['waypoints'], 'Kaloor');
    });

    test('returns null without enough information', () {
      expect(googleMapsDirectionsUri(stopNames: ['Aluva']), isNull);
      expect(googleMapsDirectionsUri(stopNames: const []), isNull);
    });
  });
}

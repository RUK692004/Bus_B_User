import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flutter_app/services/route_progress.dart';

void main() {
  // Three stops on a straight east-west road, about 1.1 km apart.
  const a = LatLng(10.0, 76.00);
  const b = LatLng(10.0, 76.01);
  const c = LatLng(10.0, 76.02);

  group('RouteProgressTracker', () {
    test('places a bus halfway between the first two stops', () {
      final progress = RouteProgressTracker([a, b, c]).update(const LatLng(10.0, 76.005));

      expect(progress.fromIndex, 0);
      expect(progress.toIndex, 1);
      expect(progress.fraction, closeTo(0.5, 0.01));
      expect(progress.atStopIndex, isNull);
      expect(progress.offRouteMetres, lessThan(1));
    });

    test('snaps a bus slightly beside the road onto the right segment', () {
      final progress = RouteProgressTracker([a, b, c]).update(const LatLng(10.0005, 76.015));

      expect(progress.fromIndex, 1);
      expect(progress.fraction, closeTo(0.5, 0.01));
      expect(progress.offRouteMetres, closeTo(55, 2));
    });

    test('reports a bus within 100 m of a stop as at that stop', () {
      final tracker = RouteProgressTracker([a, b, c]);

      expect(tracker.update(const LatLng(10.0, 76.0002)).atStopIndex, 0);
      expect(tracker.update(const LatLng(10.0, 76.0099)).atStopIndex, 1);
    });

    test('clamps a bus beyond the last stop to the destination', () {
      final progress = RouteProgressTracker([a, b, c]).update(const LatLng(10.0, 76.025));

      expect(progress.fromIndex, 1);
      expect(progress.fraction, 1.0);
      expect(progress.atStopIndex, 2);
    });

    test('measures how far a bus is from the route', () {
      final progress = RouteProgressTracker([a, b, c]).update(const LatLng(10.01, 76.005));

      expect(progress.offRouteMetres, greaterThan(1000));
    });

    test('ignores small backwards moves but accepts large ones', () {
      final tracker = RouteProgressTracker([a, b, c]);
      final first = tracker.update(const LatLng(10.0, 76.005));

      // ~22 m back: GPS jitter, keep the previous progress.
      expect(tracker.update(const LatLng(10.0, 76.0048)), same(first));

      // ~330 m back: a real move, accept it.
      final moved = tracker.update(const LatLng(10.0, 76.002));
      expect(moved.fraction, closeTo(0.2, 0.01));
      expect(tracker.current, same(moved));
    });

    test('stop distances accumulate along the route', () {
      final distances = RouteProgressTracker([a, b, c]).stopDistances;

      expect(distances.first, 0);
      expect(distances[1], closeTo(1096, 5));
      expect(distances[2], closeTo(2192, 10));
    });
  });

  test('distanceMetres matches the haversine distance', () {
    expect(distanceMetres(a, b), closeTo(1096, 5));
    expect(distanceMetres(a, a), 0);
  });
}

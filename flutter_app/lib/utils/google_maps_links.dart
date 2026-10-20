import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Builds a Google Maps driving-directions link for a bus route.
///
/// When the bus's live [busPosition] is known it is used as the origin, and the
/// remaining stops become waypoints. Returns null when there is not enough
/// information for a route.
Uri? googleMapsDirectionsUri({
  required List<String> stopNames,
  LatLng? busPosition,
}) {
  if (stopNames.length < 2 && busPosition == null) return null;

  final String origin;
  final String destination;
  var waypoints = <String>[];

  if (busPosition != null) {
    origin = '${busPosition.latitude},${busPosition.longitude}';
    destination = stopNames.isNotEmpty ? stopNames.last : origin;
    if (stopNames.length > 1) {
      waypoints = stopNames.sublist(1, stopNames.length - 1);
    }
  } else {
    origin = stopNames.first;
    destination = stopNames.last;
    if (stopNames.length > 2) {
      waypoints = stopNames.sublist(1, stopNames.length - 1);
    }
  }

  return Uri.https('www.google.com', '/maps/dir/', <String, String>{
    'api': '1',
    'origin': origin,
    'destination': destination,
    if (waypoints.isNotEmpty) 'waypoints': waypoints.join('|'),
    'travelmode': 'driving',
  });
}

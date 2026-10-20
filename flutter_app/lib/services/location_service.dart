import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// A reason the current location could not be determined, worded for the user.
class LocationException implements Exception {
  final String message;

  const LocationException(this.message);

  @override
  String toString() => 'LocationException: $message';
}

/// The device's current position plus nearby place names for display.
class CurrentLocation {
  final double latitude;
  final double longitude;

  /// Place names from reverse geocoding, most specific first. May be empty.
  final List<String> placeNames;

  const CurrentLocation({
    required this.latitude,
    required this.longitude,
    this.placeNames = const [],
  });

  String get coordinatesText =>
      '${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)}';

  /// The best short label for this location: a place name if one is known.
  String get displayName =>
      placeNames.isNotEmpty ? placeNames.first : coordinatesText;
}

/// Wraps location permissions, GPS and reverse geocoding.
class LocationService {
  const LocationService();

  /// Returns the current location, asking for permission if needed.
  ///
  /// Throws [LocationException] when location is unavailable for a reason the
  /// user can act on (services off, permission denied, no fix).
  Future<CurrentLocation> getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('Location services are turned off.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('Location permission denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Location permission permanently denied. Enable it from settings.',
      );
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (e) {
      debugPrint('[LocationService] Current position unavailable, using last known: $e');
      position = await Geolocator.getLastKnownPosition();
    }

    if (position == null) {
      throw const LocationException('Could not get current location. Try again.');
    }

    return CurrentLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      placeNames: await _placeNamesFor(position),
    );
  }

  Future<List<String>> _placeNamesFor(Position position) async {
    final List<Placemark> placemarks;
    try {
      placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
    } catch (e) {
      // Reverse geocoding may fail on web or quota limits; callers fall back to lat/lng.
      debugPrint('[LocationService] Reverse geocoding failed: $e');
      return const [];
    }
    if (placemarks.isEmpty) return const [];

    final placemark = placemarks.first;
    return <String>{
      for (final name in [
        placemark.subLocality,
        placemark.locality,
        placemark.subAdministrativeArea,
      ])
        if ((name ?? '').trim().isNotEmpty) name!.trim(),
    }.toList();
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/bus_info.dart';
import '../utils/google_maps_availability.dart';

class BusRouteDetailsScreen extends StatefulWidget {
  final BusInfo bus;

  const BusRouteDetailsScreen({super.key, required this.bus});

  @override
  State<BusRouteDetailsScreen> createState() =>
      _BusRouteDetailsScreenState();
}

class _BusRouteDetailsScreenState extends State<BusRouteDetailsScreen> {
  GoogleMapController? _mapController;
  bool _hasFittedCamera = false;
  bool _isDisposed = false;

  bool _isResolvingRoute = false;
  String? _routeError;
  bool _googleMapsLoaded = false;

  List<String> get _routePoints =>
      _buildRoutePoints(widget.bus.start, widget.bus.stops, widget.bus.end);

  final List<LatLng> _routePolylinePoints = [];
  Set<Marker> _routeStopMarkers = const {};

  late final String _busDocId;
  LatLng? _latestBusLatLng;

  @override
  void initState() {
    super.initState();
    _busDocId = widget.bus.id ?? widget.bus.number;
    _googleMapsLoaded = isGoogleMapsLoaded();
    if (!_googleMapsLoaded) {
      // Wait briefly for the JS SDK to load on the web.
      Future<void>(() async {
        for (int i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (!mounted) return;
          if (isGoogleMapsLoaded()) {
            setState(() => _googleMapsLoaded = true);
            return;
          }
        }
        if (!mounted) return;
        setState(() => _googleMapsLoaded = false);
      });
    }
    // Delay route resolution slightly so the UI (and map surface) can paint first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _resolveRoutePolyline();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _mapController = null;
    super.dispose();
  }

  List<String> _buildRoutePoints(
    String? start,
    List<String> stops,
    String? end,
  ) {
    final points = <String>[];

    if (start != null && start.trim().isNotEmpty) {
      points.add(start.trim());
    }

    for (final stop in stops) {
      if (stop.trim().isNotEmpty) {
        points.add(stop.trim());
      }
    }

    if (end != null && end.trim().isNotEmpty) {
      points.add(end.trim());
    }

    return points;
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<LatLng?> _geocodePlaceName(String place) async {
    // Try multiple query formats to improve match rate.
    final startHint = (widget.bus.start ?? '').trim();
    final endHint = (widget.bus.end ?? '').trim();
    final uniqueQueries = <String>{
      place,
      if (startHint.isNotEmpty) '$place, $startHint',
      if (endHint.isNotEmpty) '$place, $endHint',
      '$place, Kochi, Kerala, India',
      '$place, Kerala, India',
      '$place, India',
    };

    for (final query in uniqueQueries) {
      try {
        final locations = await locationFromAddress(query)
            .timeout(const Duration(seconds: 3));
        if (locations.isNotEmpty) {
          final first = locations.first;
          return LatLng(first.latitude, first.longitude);
        }
      } catch (_) {
        // Continue with next query variant.
      }
    }

    return null;
  }

  Future<void> _resolveRoutePolyline() async {
    final labels = _routePoints;
    if (labels.length < 2) {
      if (!mounted) return;
      setState(() {
        _routeError = 'Not enough route data to render the map.';
      });
      return;
    }

    setState(() {
      _isResolvingRoute = true;
      _routeError = null;
      _routePolylinePoints.clear();
      _routeStopMarkers = const {};
    });

    Map<String, dynamic>? busDocData;
    if (widget.bus.id != null) {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('buses').doc(widget.bus.id).get();
        busDocData = doc.data();
      } catch (_) {
        // Fallback to geocoding.
      }
    }

    final routeCoordinates = (busDocData?['routeCoordinates'] as List?)
            ?.whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList() ??
        const <Map<String, dynamic>>[];

    final points = <LatLng>[];
    final stopMarkers = <Marker>{};

    if (routeCoordinates.length >= 2) {
      for (var i = 0; i < routeCoordinates.length; i++) {
        final entry = routeCoordinates[i];
        final lat = _asDouble(entry['lat']);
        final lng = _asDouble(entry['lng']);
        if (lat == null || lng == null) continue;

        final name =
            (entry['name'] as String?)?.trim().isNotEmpty == true
                ? (entry['name'] as String).trim()
                : (i < labels.length ? labels[i] : 'Stop');

        final kind = (entry['kind'] as String?)?.toLowerCase();
        final isStart = kind == 'start' || i == 0;
        final isEnd = kind == 'end' || i == routeCoordinates.length - 1;

        final point = LatLng(lat, lng);
        points.add(point);

        stopMarkers.add(
          Marker(
            markerId: MarkerId('route_stop_saved_$i'),
            position: point,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isStart
                  ? BitmapDescriptor.hueGreen
                  : isEnd
                      ? BitmapDescriptor.hueRed
                      : BitmapDescriptor.hueViolet,
            ),
            infoWindow: InfoWindow(
              title: isStart
                  ? 'Start'
                  : isEnd
                      ? 'Destination'
                      : 'Stop $i',
              snippet: name,
            ),
          ),
        );
      }
    } else {
      // Geocoding fallback can be slow on mobile and may lead to ANR if it takes too long.
      // Keep it bounded.
      final int maxGeocodePoints = kIsWeb ? labels.length : 8;

      // Fallback: geocode start/stops/end place names from Firestore data.
      for (var i = 0; i < labels.length && i < maxGeocodePoints; i++) {
        final label = labels[i];
        final latLng = await _geocodePlaceName(label);
        if (latLng == null) continue;

        points.add(latLng);
        stopMarkers.add(
          Marker(
            markerId: MarkerId('route_stop_$i'),
            position: latLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              i == 0
                  ? BitmapDescriptor.hueGreen
                  : i == labels.length - 1
                      ? BitmapDescriptor.hueRed
                      : BitmapDescriptor.hueViolet,
            ),
            infoWindow: InfoWindow(
              title: i == 0
                  ? 'Start'
                  : i == labels.length - 1
                      ? 'Destination'
                      : 'Stop $i',
              snippet: label,
            ),
          ),
        );
      }

      if (labels.length > maxGeocodePoints) {
        _routeError =
            'Route has many stops. Save routeCoordinates in Firestore for faster map loading.';
      }
    }

    if (!mounted) return;
    setState(() {
      _isResolvingRoute = false;
      _routePolylinePoints.addAll(points);
      _routeStopMarkers = stopMarkers;
      if (points.length < 2) {
        _routeError = 'Could not resolve full route on map.';
      }
    });

    // If live bus position already arrived, fit the camera once we have the route polyline.
    if (!_hasFittedCamera &&
        _latestBusLatLng != null &&
        _mapController != null &&
        _routePolylinePoints.length >= 2) {
      _hasFittedCamera = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fitRouteAndBusInView(_latestBusLatLng!);
      });
    }
  }

  Future<void> _openInGoogleMaps() async {
    final routePoints = _routePoints;

    if (routePoints.length < 2 && _latestBusLatLng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Route information is incomplete for this bus.'),
        ),
      );
      return;
    }

    // Prefer the live bus location as origin if we have it.
    String origin;
    String destination;
    List<String> waypointList = [];

    if (_latestBusLatLng != null) {
      origin =
          '${_latestBusLatLng!.latitude},${_latestBusLatLng!.longitude}';
      if (routePoints.isNotEmpty) {
        destination = routePoints.last;
        if (routePoints.length > 1) {
          waypointList = routePoints.sublist(1, routePoints.length - 1);
        }
      } else {
        destination = origin;
      }
    } else {
      origin = routePoints.first;
      destination = routePoints.last;
      if (routePoints.length > 2) {
        waypointList = routePoints.sublist(1, routePoints.length - 1);
      }
    }

    final waypoints =
        waypointList.isNotEmpty ? waypointList.join('|') : null;

    final uri = Uri.https(
      'www.google.com',
      '/maps/dir/',
      <String, String>{
        'api': '1',
        'origin': origin,
        'destination': destination,
        if (waypoints != null && waypoints.isNotEmpty) 'waypoints': waypoints,
        'travelmode': 'driving',
      },
    );

    final canLaunch = await canLaunchUrl(uri);
    if (!canLaunch) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Google Maps.'),
        ),
      );
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _fitRouteAndBusInView(LatLng busPosition) {
    if (_isDisposed) return;
    final controller = _mapController;
    if (controller == null) return;
    if (_routePolylinePoints.length < 2) return;

    final points = <LatLng>[busPosition, ..._routePolylinePoints];

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    try {
      controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 60),
      );
    } catch (_) {
      // Map might have been disposed while a callback was pending.
    }
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = _routePoints;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.bus.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'Live + Route - ${widget.bus.number}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('bus_locations')
                  .doc(_busDocId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!_googleMapsLoaded) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          const Text(
                            'Loading Google Maps…',
                            style: TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'If this keeps looping, check your API key and referrer restrictions in Google Cloud Console.',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data?.data();

                final lat = (data?['lat'] as num?)?.toDouble();
                final lng = (data?['lng'] as num?)?.toDouble();
                final heading = (data?['heading'] as num?)?.toDouble() ?? 0;

                final busLatLng =
                    (lat != null && lng != null) ? LatLng(lat, lng) : null;

                // Avoid mutating state in build; keep latest position for actions
                // (e.g. Open in Google Maps) using a post-frame update.
                if (busLatLng != null &&
                    (_latestBusLatLng == null ||
                        _latestBusLatLng!.latitude != busLatLng.latitude ||
                        _latestBusLatLng!.longitude != busLatLng.longitude)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _isDisposed) return;
                    _latestBusLatLng = busLatLng;
                  });
                }

                if (!_hasFittedCamera &&
                    busLatLng != null &&
                    _routePolylinePoints.length >= 2 &&
                    _mapController != null) {
                  _hasFittedCamera = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _fitRouteAndBusInView(busLatLng);
                  });
                }

                final busMarker = busLatLng == null
                    ? <Marker>{}
                    : {
                        Marker(
                          markerId: const MarkerId('bus_live_marker'),
                          position: busLatLng,
                          rotation: heading.isFinite ? heading : 0,
                          anchor: const Offset(0.5, 0.5),
                          flat: true,
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueAzure,
                          ),
                          infoWindow: InfoWindow(
                            title: widget.bus.name,
                            snippet: 'Bus No: ${widget.bus.number}',
                          ),
                        )
                      };

                final initialCameraTarget = busLatLng ??
                    (_routePolylinePoints.isNotEmpty
                        ? _routePolylinePoints.first
                        : const LatLng(0, 0));

                return Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: initialCameraTarget,
                        zoom: 16.5,
                      ),
                      myLocationEnabled: false,
                      compassEnabled: true,
                      zoomControlsEnabled: false,
                      markers: {..._routeStopMarkers, ...busMarker},
                      polylines: _routePolylinePoints.length >= 2
                          ? {
                              Polyline(
                                polylineId:
                                    const PolylineId('bus_route_polyline'),
                                points: _routePolylinePoints,
                                color: Colors.blueAccent,
                                width: 5,
                              ),
                            }
                          : const {},
                      onMapCreated: (controller) {
                        if (_isDisposed) {
                          controller.dispose();
                          return;
                        }

                        _mapController = controller;
                        if (!_hasFittedCamera &&
                            _latestBusLatLng != null &&
                            _routePolylinePoints.length >= 2) {
                          _hasFittedCamera = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            _fitRouteAndBusInView(_latestBusLatLng!);
                          });
                        }
                      },
                    ),
                    if (_routeError != null)
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _routeError!,
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    if (busLatLng == null && _routePolylinePoints.isNotEmpty)
                      const Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Text(
                          'Waiting for live bus coordinates...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (_isResolvingRoute)
                      const Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Center(
                          child: Text(
                            'Resolving route on map...',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Route stops',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: routePoints.length,
              itemBuilder: (context, index) {
                final point = routePoints[index];
                final isFirst = index == 0;
                final isLast = index == routePoints.length - 1;

                final label = isFirst
                    ? 'Start'
                    : isLast
                        ? 'Destination'
                        : 'Stop $index';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isFirst
                            ? Icons.trip_origin
                            : isLast
                                ? Icons.flag
                                : Icons.stop_circle,
                        color: isFirst || isLast
                            ? Colors.blueAccent
                            : Colors.white60,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              point,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _openInGoogleMaps,
                  icon: const Icon(Icons.map, color: Colors.white),
                  label: const Text(
                    'Open in Google Maps',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


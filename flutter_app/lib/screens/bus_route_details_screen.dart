import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/bus_info.dart';
import '../services/bus_service.dart';
import '../services/route_resolver.dart';
import '../utils/google_maps_availability.dart';
import '../utils/google_maps_links.dart';
import '../widgets/route_stop_tile.dart';

class BusRouteDetailsScreen extends StatefulWidget {
  final BusInfo bus;
  final BusService? busService;
  final RouteResolver? routeResolver;
  final WebSocketChannel? wsChannel;

  const BusRouteDetailsScreen({
    super.key,
    required this.bus,
    this.busService,
    this.routeResolver,
    this.wsChannel,
  });

  @override
  State<BusRouteDetailsScreen> createState() => _BusRouteDetailsScreenState();
}

class _BusRouteDetailsScreenState extends State<BusRouteDetailsScreen> {
  GoogleMapController? _mapController;
  bool _hasFittedCamera = false;
  bool _isDisposed = false;

  bool _isResolvingRoute = false;
  String? _routeError;
  bool _googleMapsLoaded = false;

  late final List<String> _stopNames = widget.bus.routeStopNames;

  List<LatLng> _routePolylinePoints = const [];
  Set<Marker> _routeStopMarkers = const {};

  late final String _busId;
  LatLng? _latestBusLatLng;

  late final BusService _busService;
  late final RouteResolver _routeResolver;
  late final Stream<Map<String, dynamic>> _locationStream;

  @override
  void initState() {
    super.initState();
    _busService = widget.busService ?? BusService();
    _routeResolver = widget.routeResolver ?? RouteResolver(busService: _busService);
    _busId = widget.bus.id ?? widget.bus.number;
    _locationStream = _busService.subscribeBusLocation(
      busId: _busId,
      channel: widget.wsChannel,
    );

    _googleMapsLoaded = isGoogleMapsLoaded();
    if (!_googleMapsLoaded) {
      _waitForGoogleMaps();
    }

    // Delay route resolution slightly so the UI (and map surface) can paint first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _resolveRoute();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _mapController = null;
    super.dispose();
  }

  /// On the web the Maps JS SDK may still be loading; poll for up to ~6 s.
  Future<void> _waitForGoogleMaps() async {
    for (int i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      if (isGoogleMapsLoaded()) {
        setState(() => _googleMapsLoaded = true);
        return;
      }
    }
  }

  Future<void> _resolveRoute() async {
    setState(() {
      _isResolvingRoute = true;
      _routeError = null;
      _routePolylinePoints = const [];
      _routeStopMarkers = const {};
    });

    final route = await _routeResolver.resolve(widget.bus);
    if (!mounted) return;

    setState(() {
      _isResolvingRoute = false;
      _routePolylinePoints = route.points;
      _routeStopMarkers = {for (final stop in route.stops) _stopMarker(stop)};
      _routeError = route.warning;
    });

    // If the live bus position already arrived, fit the camera now that the route exists.
    _maybeFitCamera(_latestBusLatLng);
  }

  Marker _stopMarker(RouteStop stop) {
    return Marker(
      markerId: MarkerId('route_stop_${stop.index}'),
      position: stop.position,
      icon: BitmapDescriptor.defaultMarkerWithHue(
        switch (stop.kind) {
          RouteStopKind.start => BitmapDescriptor.hueGreen,
          RouteStopKind.end => BitmapDescriptor.hueRed,
          RouteStopKind.stop => BitmapDescriptor.hueViolet,
        },
      ),
      infoWindow: InfoWindow(title: stop.label, snippet: stop.name),
    );
  }

  Marker _busMarker(LatLng position, double heading) {
    return Marker(
      markerId: const MarkerId('bus_live_marker'),
      position: position,
      rotation: heading.isFinite ? heading : 0,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      infoWindow: InfoWindow(
        title: widget.bus.name,
        snippet: 'Bus No: ${widget.bus.number}',
      ),
    );
  }

  /// Fits the route and bus in view once, as soon as the map, the route and a
  /// bus position are all available.
  void _maybeFitCamera(LatLng? busPosition) {
    if (_hasFittedCamera ||
        busPosition == null ||
        _mapController == null ||
        _routePolylinePoints.length < 2) {
      return;
    }
    _hasFittedCamera = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitRouteAndBusInView(busPosition);
    });
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
      controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
    } catch (_) {
      // Map might have been disposed while a callback was pending.
    }
  }

  Future<void> _openInGoogleMaps() async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = googleMapsDirectionsUri(
      stopNames: _stopNames,
      busPosition: _latestBusLatLng,
    );

    if (uri == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Route information is incomplete for this bus.')),
      );
      return;
    }

    if (!await canLaunchUrl(uri)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps.')),
      );
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildMap(BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
    if (!_googleMapsLoaded) {
      return const _MapsLoadingPlaceholder();
    }
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = snapshot.data;
    final lat = (data?['lat'] as num?)?.toDouble();
    final lng = (data?['lng'] as num?)?.toDouble();
    final heading = (data?['heading'] as num?)?.toDouble() ?? 0;
    final busLatLng = (lat != null && lng != null) ? LatLng(lat, lng) : null;

    // Avoid mutating state in build; keep the latest position for actions
    // (e.g. Open in Google Maps) using a post-frame update.
    if (busLatLng != null && busLatLng != _latestBusLatLng) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed) return;
        _latestBusLatLng = busLatLng;
      });
    }
    _maybeFitCamera(busLatLng);

    final initialCameraTarget = busLatLng ??
        (_routePolylinePoints.isNotEmpty ? _routePolylinePoints.first : const LatLng(0, 0));

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: initialCameraTarget, zoom: 16.5),
          myLocationEnabled: false,
          compassEnabled: true,
          zoomControlsEnabled: false,
          markers: {
            ..._routeStopMarkers,
            if (busLatLng != null) _busMarker(busLatLng, heading),
          },
          polylines: _routePolylinePoints.length >= 2
              ? {
                  Polyline(
                    polylineId: const PolylineId('bus_route_polyline'),
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
            _maybeFitCamera(_latestBusLatLng);
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
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
          ),
        if (busLatLng == null && _routePolylinePoints.isNotEmpty)
          const _MapStatusText('Waiting for live bus coordinates...'),
        if (_isResolvingRoute) const _MapStatusText('Resolving route on map...'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.bus.name,
              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
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
            child: StreamBuilder<Map<String, dynamic>>(
              key: ValueKey(_busId),
              stream: _locationStream,
              builder: _buildMap,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Route stops',
                style: TextStyle(
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
              itemCount: _stopNames.length,
              itemBuilder: (context, index) => RouteStopTile(
                name: _stopNames[index],
                index: index,
                totalStops: _stopNames.length,
              ),
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

class _MapsLoadingPlaceholder extends StatelessWidget {
  const _MapsLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Loading Google Maps…',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Text(
              'If this keeps looping, check your API key and referrer restrictions in Google Cloud Console.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A short status line pinned to the bottom of the map.
class _MapStatusText extends StatelessWidget {
  final String text;

  const _MapStatusText(this.text);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

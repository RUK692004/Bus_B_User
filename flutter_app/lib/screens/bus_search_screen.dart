import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/bus_info.dart';
import 'bus_route_details_screen.dart';
import 'settings_screen.dart';

class BusSearchScreen extends StatefulWidget {
  const BusSearchScreen({super.key});

  @override
  State<BusSearchScreen> createState() => _BusSearchScreenState();
}

class _BusSearchScreenState extends State<BusSearchScreen> {
  bool _isFetchingLocation = false;
  bool _isSearchingBus = false;
  bool _isSearchingTrips = false;

  String? _locationLabel;
  String? _errorMessage;

  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _busSearchController = TextEditingController();

  List<BusInfo> _trackedBuses = [];

  @override
  void dispose() {
    _fromController.dispose();
    _destinationController.dispose();
    _busSearchController.dispose();
    super.dispose();
  }

  String _normalizeText(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  List<String> _buildRoutePoints({
    String? start,
    List<String> stops = const [],
    String? end,
  }) {
    final List<String> routePoints = [];

    if (start != null && start.trim().isNotEmpty) {
      routePoints.add(start.trim());
    }

    for (final stop in stops) {
      if (stop.trim().isNotEmpty) {
        routePoints.add(stop.trim());
      }
    }

    if (end != null && end.trim().isNotEmpty) {
      routePoints.add(end.trim());
    }

    return routePoints;
  }

  BusInfo _mapBusFromFirestore(
    Map<String, dynamic> data, {
    double distanceKm = 0,
  }) {
    final stops =
        (data['stops'] as List?)?.map((e) => e.toString()).toList() ?? [];

    final busNumber =
        (data['busNumber'] as String?)?.trim().toUpperCase() ?? 'UNKNOWN';

    return BusInfo(
      name: (data['busName'] as String?)?.trim().isNotEmpty == true
          ? (data['busName'] as String).trim()
          : (data['routeName'] as String?)?.trim().isNotEmpty == true
          ? (data['routeName'] as String).trim()
          : 'Bus $busNumber',
      number: busNumber,
      distanceKm: distanceKm,
      start: data['start'] as String?,
      end: data['end'] as String?,
      stops: stops,
    );
  }

  bool _doesBusMatchRoute({
    required String from,
    required String destination,
    required String? start,
    required List<String> stops,
    required String? end,
  }) {
    final routePoints = _buildRoutePoints(start: start, stops: stops, end: end);

    final normalizedRoute = routePoints
        .map((point) => _normalizeText(point))
        .toList();

    final normalizedFrom = _normalizeText(from);
    final normalizedDestination = _normalizeText(destination);

    final fromIndex = normalizedRoute.indexOf(normalizedFrom);
    final destinationIndex = normalizedRoute.indexOf(normalizedDestination);

    if (fromIndex == -1 || destinationIndex == -1) {
      return false;
    }

    return fromIndex < destinationIndex;
  }

  Future<void> _fetchLocationAndNearbyBuses() async {
    if (_isFetchingLocation) return;

    setState(() {
      _isFetchingLocation = true;
      _errorMessage = null;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        setState(() {
          _errorMessage = 'Location permission denied.';
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage =
              'Location permission permanently denied. Enable it from settings.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition();

      setState(() {
        _locationLabel =
            '${position.latitude.toStringAsFixed(3)}, ${position.longitude.toStringAsFixed(3)}';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to fetch location.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingLocation = false;
        });
      }
    }
  }

  Future<void> _searchBusByNumber() async {
    final query = _busSearchController.text.trim();

    if (query.isEmpty) {
      setState(() {
        _trackedBuses = [];
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isSearchingBus = true;
      _errorMessage = null;
      _trackedBuses = [];
    });

    try {
      final formattedQuery = query.toUpperCase();

      final snap = await FirebaseFirestore.instance
          .collection('buses')
          .where('busNumber', isEqualTo: formattedQuery)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        setState(() {
          _errorMessage = 'No bus found with that number.';
        });
        return;
      }

      final data = snap.docs.first.data();

      setState(() {
        _trackedBuses = [_mapBusFromFirestore(data)];
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to fetch bus details. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingBus = false;
        });
      }
    }
  }

  Future<void> _searchTrips() async {
    final from = _fromController.text.trim();
    final destination = _destinationController.text.trim();

    if (from.isEmpty || destination.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both starting point and destination.';
      });
      return;
    }

    if (_normalizeText(from) == _normalizeText(destination)) {
      setState(() {
        _errorMessage = 'Starting point and destination cannot be the same.';
      });
      return;
    }

    setState(() {
      _isSearchingTrips = true;
      _errorMessage = null;
      _trackedBuses = [];
    });

    try {
      final snap = await FirebaseFirestore.instance.collection('buses').get();

      final List<BusInfo> matchedBuses = [];

      for (final doc in snap.docs) {
        final data = doc.data();

        final stops =
            (data['stops'] as List?)?.map((e) => e.toString()).toList() ?? [];

        final start = data['start'] as String?;
        final end = data['end'] as String?;

        final matches = _doesBusMatchRoute(
          from: from,
          destination: destination,
          start: start,
          stops: stops,
          end: end,
        );

        if (matches) {
          matchedBuses.add(_mapBusFromFirestore(data));
        }
      }

      setState(() {
        _trackedBuses = matchedBuses;
        if (matchedBuses.isEmpty) {
          _errorMessage = 'No buses found for this route.';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to search trips. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingTrips = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.directions_bus,
                          color: Colors.white,
                          size: 28,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'BusBee',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(30),
                          onTap: _fetchLocationAndNearbyBuses,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.my_location,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                if (_isFetchingLocation)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white70,
                                    ),
                                  )
                                else
                                  Text(
                                    _locationLabel ?? 'Use my location',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white70),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _fromController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'From',
                          hintStyle: TextStyle(color: Colors.white54),
                          border: InputBorder.none,
                          icon: Icon(
                            Icons.circle_outlined,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white24),
                      TextField(
                        controller: _destinationController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Destination',
                          hintStyle: TextStyle(color: Colors.white54),
                          border: InputBorder.none,
                          icon: Icon(Icons.location_on, color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2C2C2C),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: _isSearchingTrips ? null : _searchTrips,
                          child: _isSearchingTrips
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Search Trips',
                                  style: TextStyle(color: Colors.white),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                ],

                const SizedBox(height: 25),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.white54),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _busSearchController,
                          style: const TextStyle(color: Colors.white),
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            hintText: 'Search by Bus No.',
                            hintStyle: TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _searchBusByNumber(),
                        ),
                      ),
                      _isSearchingBus
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white54,
                              ),
                            )
                          : IconButton(
                              icon: const Icon(
                                Icons.arrow_forward_ios,
                                color: Colors.white54,
                                size: 18,
                              ),
                              onPressed: _searchBusByNumber,
                            ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                const Text(
                  'Tracking Buses',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 20),

                if (_trackedBuses.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C2C2C),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(
                            Icons.directions_bus,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 15),
                        const Expanded(
                          child: Text(
                            'Search for a bus number or enter a route to see matching buses here.',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    children: _trackedBuses
                        .map((bus) => _BusCard(bus: bus))
                        .toList(),
                  ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BusCard extends StatelessWidget {
  final BusInfo bus;

  const _BusCard({required this.bus});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BusRouteDetailsScreen(bus: bus),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2C),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.directions_bus, color: Colors.white),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bus.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bus No: ${bus.number}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  if (bus.start != null && bus.end != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Route: ${bus.start} → ${bus.end}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                  if (bus.stops.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Stops: ${bus.stops.join(', ')}',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    '${bus.distanceKm.toStringAsFixed(1)} km away',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }
}

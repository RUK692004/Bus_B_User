import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
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
  static const double _nearbyBusRadiusKm = 2.0;

  bool _isFetchingLocation = false;
  bool _isSearchingBus = false;
  bool _isSearchingTrips = false;

  String? _locationLabel;
  String? _errorMessage;

  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _busSearchController = TextEditingController();

  List<BusInfo> _trackedBuses = [];
  List<String> _fromLocationSuggestions = [];

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

  List<String> _buildSearchCandidates(String input) {
    final normalizedInput = _normalizeText(input);
    final parts = input
        .split(RegExp(r'[,/-]'))
        .map((part) => _normalizeText(part))
        .where((part) => part.isNotEmpty)
        .toList();

    final candidates = <String>[normalizedInput, ...parts];

    // Include location-based hints if the user selected current location.
    if (_fromController.text.trim() == input.trim() && input.isNotEmpty) {
      candidates.addAll(
        _fromLocationSuggestions.map((s) => _normalizeText(s)).where(
              (s) => s.isNotEmpty,
            ),
      );
    }

    return candidates.toSet().toList();
  }

  int _findBestIndex(List<String> normalizedRoute, List<String> candidates) {
    for (final candidate in candidates) {
      final exactIndex = normalizedRoute.indexOf(candidate);
      if (exactIndex != -1) return exactIndex;
    }

    for (final candidate in candidates) {
      final containsIndex = normalizedRoute.indexWhere(
        (point) => point.contains(candidate) || candidate.contains(point),
      );
      if (containsIndex != -1) return containsIndex;
    }

    return -1;
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
    String? id,
    double distanceKm = 0,
  }) {
    final stops =
        (data['stops'] as List?)?.map((e) => e.toString()).toList() ?? [];

    final busNumber =
        (data['busNumber'] as String?)?.trim().toUpperCase() ?? 'UNKNOWN';

    return BusInfo(
      id: id,
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

    final fromCandidates = _buildSearchCandidates(from);
    final destinationCandidates = _buildSearchCandidates(destination);

    final fromIndex = _findBestIndex(normalizedRoute, fromCandidates);
    final destinationIndex = _findBestIndex(
      normalizedRoute,
      destinationCandidates,
    );

    if (fromIndex == -1 || destinationIndex == -1) {
      return false;
    }

    return fromIndex < destinationIndex;
  }

  Future<List<BusInfo>> _fetchBusesNearUserPosition(
    Position userPosition,
  ) async {
    final busLocationsSnap =
        await FirebaseFirestore.instance.collection('bus_locations').get();
    if (busLocationsSnap.docs.isEmpty) return const [];

    final busesCollection = FirebaseFirestore.instance.collection('buses');
    final List<BusInfo> nearbyBuses = [];

    for (final locationDoc in busLocationsSnap.docs) {
      final locationData = locationDoc.data();
      final lat = (locationData['lat'] as num?)?.toDouble();
      final lng = (locationData['lng'] as num?)?.toDouble();

      if (lat == null || lng == null) continue;

      final distanceMeters = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        lat,
        lng,
      );
      final distanceKm = distanceMeters / 1000.0;

      if (distanceKm > _nearbyBusRadiusKm) continue;

      final busDoc = await busesCollection.doc(locationDoc.id).get();
      if (!busDoc.exists) continue;

      nearbyBuses.add(
        _mapBusFromFirestore(
          busDoc.data()!,
          id: busDoc.id,
          distanceKm: distanceKm,
        ),
      );
    }

    nearbyBuses.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return nearbyBuses;
  }

  Future<void> _fetchLocationAndNearbyBuses() async {
    if (_isFetchingLocation) return;

    setState(() {
      _isFetchingLocation = true;
      _errorMessage = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorMessage = 'Location services are turned off.';
        });
        return;
      }

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

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        setState(() {
          _errorMessage = 'Could not get current location. Try again.';
        });
        return;
      }

      List<Placemark> placemarks = const [];
      try {
        placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
      } catch (_) {
        // Reverse geocoding may fail on web or quota limits; fallback to lat/lng.
      }

      final placemark = placemarks.isNotEmpty ? placemarks.first : null;
      final subLocality = (placemark?.subLocality ?? '').trim();
      final locality = (placemark?.locality ?? '').trim();
      final subAdminArea = (placemark?.subAdministrativeArea ?? '').trim();

      final suggestions = <String>{
        if (subLocality.isNotEmpty) subLocality,
        if (locality.isNotEmpty) locality,
        if (subAdminArea.isNotEmpty) subAdminArea,
      }.toList();

      final coordinatesText = '${position.latitude.toStringAsFixed(3)}, '
          '${position.longitude.toStringAsFixed(3)}';
      
      final primaryLocationName = suggestions.isNotEmpty
          ? suggestions.first
          : coordinatesText;

      setState(() {
        _locationLabel = coordinatesText;
        _fromController.text = primaryLocationName;
        _fromLocationSuggestions = suggestions;
        _errorMessage = null;
      });

      final nearbyBuses = await _fetchBusesNearUserPosition(position);
      if (!mounted) return;

      setState(() {
        _trackedBuses = nearbyBuses;
        if (nearbyBuses.isEmpty) {
          _errorMessage =
              'No live buses found near your location right now.';
        }
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

  Future<void> _useCurrentLocationAsFrom() async {
    await _fetchLocationAndNearbyBuses();
    if (!mounted) return;

    if (_fromLocationSuggestions.isNotEmpty) {
      setState(() {
        _fromController.text = _fromLocationSuggestions.first;
      });
      return;
    }

    if ((_locationLabel ?? '').trim().isNotEmpty) {
      setState(() {
        _fromController.text = _locationLabel!.trim();
      });
    }

    if (_fromController.text.trim().isNotEmpty &&
        _destinationController.text.trim().isNotEmpty) {
      await _searchTrips();
    }
  }

  Future<void> _showFromSuggestions() async {
    if (_isFetchingLocation) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF151515),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.my_location, color: Colors.white70),
                  title: const Text(
                    'Use your location',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pop(context, 'use_location'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == 'use_location') {
      await _useCurrentLocationAsFrom();
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
      final docId = snap.docs.first.id;

      setState(() {
        _trackedBuses = [_mapBusFromFirestore(data, id: docId)];
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
          matchedBuses.add(_mapBusFromFirestore(data, id: doc.id));
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
                        onTap: _showFromSuggestions,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'From',
                          hintStyle: const TextStyle(color: Colors.white54),
                          border: InputBorder.none,
                          icon: const Icon(
                            Icons.circle_outlined,
                            color: Colors.white70,
                          ),
                          suffixIcon: IconButton(
                            onPressed: _isFetchingLocation
                                ? null
                                : _useCurrentLocationAsFrom,
                            icon: _isFetchingLocation
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white70,
                                    ),
                                  )
                                : const Icon(
                                    Icons.my_location,
                                    color: Colors.white70,
                                  ),
                            tooltip: 'Use current location',
                          ),
                        ),
                      ),
                      if (_fromLocationSuggestions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _fromLocationSuggestions
                                .map(
                                  (suggestion) => ActionChip(
                                    label: Text(suggestion),
                                    avatar: const Icon(
                                      Icons.place,
                                      size: 16,
                                      color: Colors.white70,
                                    ),
                                    labelStyle:
                                        const TextStyle(color: Colors.white),
                                    backgroundColor: const Color(0xFF2C2C2C),
                                    side: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _fromController.text = suggestion;
                                      });
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
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

import 'package:flutter/material.dart';

import '../models/bus_info.dart';
import '../services/api_client.dart';
import '../services/bus_service.dart';
import '../services/location_service.dart';
import '../widgets/bus_card.dart';
import 'bus_route_details_screen.dart';
import 'settings_screen.dart';

class BusSearchScreen extends StatefulWidget {
  final BusService? busService;
  final LocationService? locationService;

  const BusSearchScreen({super.key, this.busService, this.locationService});

  @override
  State<BusSearchScreen> createState() => _BusSearchScreenState();
}

class _BusSearchScreenState extends State<BusSearchScreen> {
  static const double _nearbyBusRadiusKm = 2.0;

  late final BusService _busService;
  late final LocationService _locationService;

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
  void initState() {
    super.initState();
    _busService = widget.busService ?? BusService();
    _locationService = widget.locationService ?? const LocationService();
  }

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

  Future<void> _fetchLocationAndNearbyBuses() async {
    if (_isFetchingLocation) return;

    setState(() {
      _isFetchingLocation = true;
      _errorMessage = null;
    });

    try {
      final location = await _locationService.getCurrentLocation();
      if (!mounted) return;

      setState(() {
        _locationLabel = location.coordinatesText;
        _fromController.text = location.displayName;
        _fromLocationSuggestions = location.placeNames;
        _errorMessage = null;
      });

      final List<BusInfo> nearbyBuses;
      try {
        nearbyBuses = await _busService.getNearbyBuses(
          lat: location.latitude,
          lng: location.longitude,
          radiusMeters: _nearbyBusRadiusKm * 1000.0,
        );
      } catch (e) {
        debugPrint('[BusSearch] Nearby buses request failed: $e');
        if (!mounted) return;
        setState(() {
          _trackedBuses = [];
          _errorMessage = 'Could not load nearby buses. Please try again.';
        });
        return;
      }
      if (!mounted) return;

      setState(() {
        _trackedBuses = nearbyBuses;
        if (nearbyBuses.isEmpty) {
          _errorMessage = 'No live buses found near your location right now.';
        }
      });
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      debugPrint('[BusSearch] Fetching location failed: $e');
      if (!mounted) return;
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
      builder: (context) => const _UseLocationSheet(),
    );

    if (action == _UseLocationSheet.useLocation) {
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
      final bus = await _busService.searchBusByNumber(query);
      if (!mounted) return;

      setState(() {
        if (bus != null) {
          _trackedBuses = [bus];
          _errorMessage = null;
        } else {
          _trackedBuses = [];
          _errorMessage = 'No bus found with that number.';
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _trackedBuses = [];
        if (e.statusCode == 404) {
          _errorMessage = 'No bus found with that number.';
        } else {
          _errorMessage = e.message;
        }
      });
    } catch (e) {
      debugPrint('[BusSearch] Bus number search failed: $e');
      if (!mounted) return;
      setState(() {
        _trackedBuses = [];
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
      final matchedBuses = await _busService.searchTrips(
        from: from,
        to: destination,
      );

      if (!mounted) return;

      setState(() {
        _trackedBuses = matchedBuses;
        if (matchedBuses.isEmpty) {
          _errorMessage = 'No buses found for this route.';
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _trackedBuses = [];
        _errorMessage = e.message;
      });
    } catch (e) {
      debugPrint('[BusSearch] Trip search failed: $e');
      if (!mounted) return;
      setState(() {
        _trackedBuses = [];
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

  void _openBusDetails(BusInfo bus) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BusRouteDetailsScreen(bus: bus, busService: _busService),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
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
                _Header(onSettingsPressed: _openSettings),
                const SizedBox(height: 30),
                _TripSearchCard(
                  fromController: _fromController,
                  destinationController: _destinationController,
                  locationSuggestions: _fromLocationSuggestions,
                  isFetchingLocation: _isFetchingLocation,
                  isSearchingTrips: _isSearchingTrips,
                  onFromTap: _showFromSuggestions,
                  onUseCurrentLocation: _useCurrentLocationAsFrom,
                  onSuggestionSelected: (suggestion) {
                    setState(() {
                      _fromController.text = suggestion;
                    });
                  },
                  onSearch: _searchTrips,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 25),
                _BusNumberSearchBar(
                  controller: _busSearchController,
                  isSearching: _isSearchingBus,
                  onSearch: _searchBusByNumber,
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
                  const _EmptyResults()
                else
                  Column(
                    children: [
                      for (final bus in _trackedBuses)
                        BusCard(bus: bus, onTap: () => _openBusDetails(bus)),
                    ],
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

class _Header extends StatelessWidget {
  final VoidCallback onSettingsPressed;

  const _Header({required this.onSettingsPressed});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Row(
          children: [
            Icon(Icons.directions_bus, color: Colors.white, size: 28),
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
          onPressed: onSettingsPressed,
        ),
      ],
    );
  }
}

class _UseLocationSheet extends StatelessWidget {
  static const useLocation = 'use_location';

  const _UseLocationSheet();

  @override
  Widget build(BuildContext context) {
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
              onTap: () => Navigator.pop(context, useLocation),
            ),
          ],
        ),
      ),
    );
  }
}

/// "From" / "Destination" inputs, location suggestions and the search button.
class _TripSearchCard extends StatelessWidget {
  final TextEditingController fromController;
  final TextEditingController destinationController;
  final List<String> locationSuggestions;
  final bool isFetchingLocation;
  final bool isSearchingTrips;
  final VoidCallback onFromTap;
  final VoidCallback onUseCurrentLocation;
  final ValueChanged<String> onSuggestionSelected;
  final VoidCallback onSearch;

  const _TripSearchCard({
    required this.fromController,
    required this.destinationController,
    required this.locationSuggestions,
    required this.isFetchingLocation,
    required this.isSearchingTrips,
    required this.onFromTap,
    required this.onUseCurrentLocation,
    required this.onSuggestionSelected,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        children: [
          TextField(
            controller: fromController,
            onTap: onFromTap,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'From',
              hintStyle: const TextStyle(color: Colors.white54),
              border: InputBorder.none,
              icon: const Icon(Icons.circle_outlined, color: Colors.white70),
              suffixIcon: IconButton(
                onPressed: isFetchingLocation ? null : onUseCurrentLocation,
                icon: isFetchingLocation
                    ? const _SmallSpinner(size: 18, color: Colors.white70)
                    : const Icon(Icons.my_location, color: Colors.white70),
                tooltip: 'Use current location',
              ),
            ),
          ),
          if (locationSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final suggestion in locationSuggestions)
                    ActionChip(
                      label: Text(suggestion),
                      avatar: const Icon(Icons.place, size: 16, color: Colors.white70),
                      labelStyle: const TextStyle(color: Colors.white),
                      backgroundColor: const Color(0xFF2C2C2C),
                      side: const BorderSide(color: Colors.white24),
                      onPressed: () => onSuggestionSelected(suggestion),
                    ),
                ],
              ),
            ),
          ],
          const Divider(color: Colors.white24),
          TextField(
            controller: destinationController,
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
              onPressed: isSearchingTrips ? null : onSearch,
              child: isSearchingTrips
                  ? const _SmallSpinner(size: 20, color: Colors.white)
                  : const Text(
                      'Search Trips',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusNumberSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSearching;
  final VoidCallback onSearch;

  const _BusNumberSearchBar({
    required this.controller,
    required this.isSearching,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
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
              controller: controller,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'Search by Bus No.',
                hintStyle: TextStyle(color: Colors.white54),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => onSearch(),
            ),
          ),
          isSearching
              ? const _SmallSpinner(size: 18, color: Colors.white54)
              : IconButton(
                  icon: const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white54,
                    size: 18,
                  ),
                  onPressed: onSearch,
                ),
        ],
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    return Container(
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
            child: const Icon(Icons.directions_bus, color: Colors.white),
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Text(
              'Search for a bus number or enter a route to see matching buses here.',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallSpinner extends StatelessWidget {
  final double size;
  final Color color;

  const _SmallSpinner({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}

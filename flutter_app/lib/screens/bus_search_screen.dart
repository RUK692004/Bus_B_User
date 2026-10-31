import 'package:flutter/material.dart';

import '../models/bus_info.dart';
import '../services/api_client.dart';
import '../services/bus_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';
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
  final FocusNode _busSearchFocus = FocusNode();

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
    _busSearchFocus.dispose();
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
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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

  void _swapFromAndDestination() {
    setState(() {
      final from = _fromController.text;
      _fromController.text = _destinationController.text;
      _destinationController.text = from;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFF4B8), Color(0xFFFBE3F6), AppColors.paper],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const BrandWordmark(),
                          RoundIconButton(
                            icon: Icons.settings_outlined,
                            tooltip: 'Settings',
                            outlined: true,
                            onPressed: _openSettings,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const AccentBanner(text: 'Where are you headed today?'),
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
                      TileGrid(
                        items: [
                          GridTileItem(
                            label: 'Nearby buses',
                            icon: Icons.near_me_outlined,
                            iconColor: AppColors.violet,
                            onTap: _fetchLocationAndNearbyBuses,
                          ),
                          GridTileItem(
                            label: 'Bus number',
                            icon: Icons.tag,
                            onTap: _busSearchFocus.requestFocus,
                          ),
                          GridTileItem(
                            label: 'Swap From / To',
                            icon: Icons.swap_vert,
                            onTap: _swapFromAndDestination,
                          ),
                          GridTileItem(
                            label: 'Settings',
                            icon: Icons.tune,
                            onTap: _openSettings,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const TickerBand(text: 'Live bus tracking  ✨  Search by route  ✨  Follow your bus in real time'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 20),
                    InlineMessage(_errorMessage!),
                  ],
                  const SquiggleDivider(),
                  const Text('Find by bus number', style: AppText.title),
                  const SizedBox(height: 6),
                  const Text('Know the number on the board? Jump straight to it.', style: AppText.secondary),
                  const SizedBox(height: 18),
                  _BusNumberSearchBar(
                    controller: _busSearchController,
                    focusNode: _busSearchFocus,
                    isSearching: _isSearchingBus,
                    onSearch: _searchBusByNumber,
                  ),
                  const SquiggleDivider(),
                  Row(
                    children: [
                      const Expanded(child: Text('Tracking buses', style: AppText.title)),
                      if (_trackedBuses.isNotEmpty) Pill('${_trackedBuses.length} FOUND'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_trackedBuses.isEmpty)
                    const _EmptyResults()
                  else
                    for (final bus in _trackedBuses)
                      BusCard(bus: bus, onTap: () => _openBusDetails(bus)),
                  const SquiggleDivider(),
                  const FadedFooter(text: 'Safe\ntravels!'),
                ],
              ),
            ),
          ],
        ),
      ),
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
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text('Starting point', style: AppText.heading),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const RoundIconButton(icon: Icons.my_location, size: 44),
              title: const Text('Use your location', style: AppText.body),
              subtitle: const Text('Find the nearest place names', style: AppText.secondary),
              onTap: () => Navigator.pop(context, useLocation),
            ),
          ],
        ),
      ),
    );
  }
}

/// "From" / "Destination" inputs, location suggestions and the search button,
/// in an outlined box that sits under the accent banner.
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

  static const _bare = InputDecoration(
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    filled: false,
    contentPadding: EdgeInsets.symmetric(vertical: 18),
  );

  @override
  Widget build(BuildContext context) {
    const side = BorderSide(color: AppColors.ink, width: AppTheme.outline);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(left: side, right: side),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: fromController,
            onTap: onFromTap,
            style: AppText.body.copyWith(fontSize: 16),
            decoration: _bare.copyWith(
              hintText: 'From',
              prefixIcon: const Icon(Icons.trip_origin, color: AppColors.ink),
              suffixIcon: IconButton(
                onPressed: isFetchingLocation ? null : onUseCurrentLocation,
                icon: isFetchingLocation
                    ? const _SmallSpinner(size: 18, color: AppColors.ink)
                    : const Icon(Icons.my_location, color: AppColors.ink),
                tooltip: 'Use current location',
              ),
            ),
          ),
          if (locationSuggestions.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in locationSuggestions)
                  ActionChip(
                    label: Text(suggestion),
                    avatar: const Icon(Icons.place_outlined, size: 16, color: AppColors.ink),
                    onPressed: () => onSuggestionSelected(suggestion),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          const Divider(color: AppColors.ink, thickness: AppTheme.outline, height: AppTheme.outline),
          TextField(
            controller: destinationController,
            style: AppText.body.copyWith(fontSize: 16),
            decoration: _bare.copyWith(
              hintText: 'Destination',
              prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.ink),
            ),
          ),
          const Divider(color: AppColors.ink, thickness: AppTheme.outline, height: AppTheme.outline),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: isSearchingTrips ? null : onSearch,
            child: isSearchingTrips
                ? const _SmallSpinner(size: 20, color: AppColors.paper)
                : const Text('Search Trips'),
          ),
        ],
      ),
    );
  }
}

/// Outlined pill search field with a round black "go" button.
class _BusNumberSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final VoidCallback onSearch;

  const _BusNumberSearchBar({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
      decoration: ShapeDecoration(
        color: AppColors.paper,
        shape: StadiumBorder(
          side: BorderSide(color: AppColors.ink, width: AppTheme.outline),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppColors.ink),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: AppText.body.copyWith(fontSize: 16),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'Search by Bus No.',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              onSubmitted: (_) => onSearch(),
            ),
          ),
          SizedBox(
            width: 46,
            height: 46,
            child: isSearching
                ? const Center(child: _SmallSpinner(size: 20, color: AppColors.ink))
                : Material(
                    color: AppColors.ink,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, color: AppColors.paper, size: 16),
                      onPressed: onSearch,
                    ),
                  ),
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
    return OutlinedPanel(
      child: Row(
        children: [
          const RoundIconButton(icon: Icons.directions_bus_outlined, size: 48),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Search for a bus number or enter a route to see matching buses here.',
              style: AppText.secondary.copyWith(fontSize: 15),
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

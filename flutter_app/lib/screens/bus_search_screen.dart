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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: AppColors.border, width: AppTheme.hairline),
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
            GlowBackdrop(
              style: GlowStyle.horizon,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NavBarPill(
                        trailing: RoundIconButton(
                          icon: Icons.settings_outlined,
                          tooltip: 'Settings',
                          size: 40,
                          onPressed: _openSettings,
                        ),
                      ),
                      const SizedBox(height: 48),
                      Center(
                        child: AnnouncementPill(
                          'Live buses around you',
                          actionLabel: 'Nearby',
                          onTap: _fetchLocationAndNearbyBuses,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const GradientHeadline('Where is\nyour bus?'),
                      const SizedBox(height: 12),
                      Text(
                        'Search a route or a bus number and follow it live, stop by stop.',
                        textAlign: TextAlign.center,
                        style: AppText.secondary.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 28),
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
                        onSwap: _swapFromAndDestination,
                        onNearby: _fetchLocationAndNearbyBuses,
                        onSearch: _searchTrips,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage != null) ...[
                    InlineMessage(_errorMessage!),
                    const SizedBox(height: 28),
                  ],
                  const SectionHeader(
                    'Find by bus number',
                    subtitle: 'Know the number on the board? Jump straight to it.',
                  ),
                  const SizedBox(height: 16),
                  _BusNumberSearchBar(
                    controller: _busSearchController,
                    focusNode: _busSearchFocus,
                    isSearching: _isSearchingBus,
                    onSearch: _searchBusByNumber,
                  ),
                  const SizedBox(height: 40),
                  SectionHeader(
                    'Tracking buses',
                    trailing: _trackedBuses.isEmpty ? null : Pill('${_trackedBuses.length} found', accent: true),
                  ),
                  const SizedBox(height: 16),
                  if (_trackedBuses.isEmpty)
                    const _EmptyResults()
                  else
                    for (final bus in _trackedBuses)
                      BusCard(bus: bus, onTap: () => _openBusDetails(bus)),
                  const SizedBox(height: 36),
                  Center(
                    child: Text(
                      'BusBee · Live bus tracking around Kochi',
                      style: AppText.secondary.copyWith(color: AppColors.faint, fontSize: 13),
                    ),
                  ),
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
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text('Starting point', style: AppText.heading),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const RoundIconButton(icon: Icons.my_location),
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

/// "From" / "Destination" inputs with a swap button, location suggestions,
/// and the silver search button, in a dark panel over the glow.
class _TripSearchCard extends StatelessWidget {
  final TextEditingController fromController;
  final TextEditingController destinationController;
  final List<String> locationSuggestions;
  final bool isFetchingLocation;
  final bool isSearchingTrips;
  final VoidCallback onFromTap;
  final VoidCallback onUseCurrentLocation;
  final ValueChanged<String> onSuggestionSelected;
  final VoidCallback onSwap;
  final VoidCallback onNearby;
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
    required this.onSwap,
    required this.onNearby,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    TextField(
                      controller: fromController,
                      onTap: onFromTap,
                      style: AppText.body.copyWith(fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'From',
                        prefixIcon: const Icon(Icons.trip_origin, size: 20),
                        suffixIcon: IconButton(
                          onPressed: isFetchingLocation ? null : onUseCurrentLocation,
                          icon: isFetchingLocation
                              ? const _SmallSpinner(size: 18, color: AppColors.text)
                              : const Icon(Icons.my_location, color: AppColors.ember),
                          tooltip: 'Use current location',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: destinationController,
                      style: AppText.body.copyWith(fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Destination',
                        prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              RoundIconButton(
                icon: Icons.swap_vert,
                tooltip: 'Swap From / To',
                size: 40,
                onPressed: onSwap,
              ),
            ],
          ),
          if (locationSuggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in locationSuggestions)
                  ActionChip(
                    label: Text(suggestion),
                    avatar: const Icon(Icons.place_outlined),
                    onPressed: () => onSuggestionSelected(suggestion),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: isSearchingTrips ? null : onSearch,
                  child: isSearchingTrips
                      ? const _SmallSpinner(size: 20, color: AppColors.onLight)
                      : const Text('Search Trips'),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: isFetchingLocation ? null : onNearby,
                child: const Text('Nearby buses'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Hairline search field with a round silver "go" button.
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
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: AppTheme.hairline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppColors.muted),
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
            width: 44,
            height: 44,
            child: isSearching
                ? const Center(child: _SmallSpinner(size: 20, color: AppColors.text))
                : DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: AppTheme.silverGradient,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, color: AppColors.onLight, size: 16),
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
    return GlassPanel(
      child: Row(
        children: [
          const RoundIconButton(icon: Icons.directions_bus_outlined),
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

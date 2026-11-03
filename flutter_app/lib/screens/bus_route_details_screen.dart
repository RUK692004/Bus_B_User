import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/bus_info.dart';
import '../services/bus_service.dart';
import '../services/route_progress.dart';
import '../services/route_resolver.dart';
import '../theme/app_theme.dart';
import '../utils/google_maps_links.dart';
import '../widgets/brand.dart';
import '../widgets/route_timeline_tile.dart';

/// Live route of one bus as a vertical stop timeline ("Where is my Train"
/// style), with a button that opens the route in Google Maps.
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
  /// A location older than this is shown as "last seen" with a grey bus.
  static const _staleAfter = Duration(minutes: 2);

  /// Further than this from the route, the bus is flagged as off route.
  static const _offRouteMetres = 300.0;

  late final BusService _busService;
  late final RouteResolver _routeResolver;
  late final String _busId;
  late final List<String> _stopNames = widget.bus.routeStopNames;
  StreamSubscription<Map<String, dynamic>>? _locationSubscription;

  /// Refreshes the "updated Xs ago" text.
  Timer? _clock;
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolledToBus = false;

  bool _isResolvingRoute = true;
  String? _routeWarning;

  /// Stops with map positions, once the route is resolved.
  List<RouteStop> _routeStops = const [];
  RouteProgressTracker? _tracker;
  RouteProgress? _progress;

  LatLng? _latestBusLatLng;
  DateTime? _lastUpdate;

  @override
  void initState() {
    super.initState();
    _busService = widget.busService ?? BusService();
    _routeResolver = widget.routeResolver ?? RouteResolver(busService: _busService);
    _busId = widget.bus.id ?? widget.bus.number;

    _locationSubscription = _busService
        .subscribeBusLocation(busId: _busId, channel: widget.wsChannel)
        .listen(_onLocation, onError: (Object e) {
      debugPrint('[BusRouteDetails] Live location stream error: $e');
    });
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _lastUpdate != null) setState(() {});
    });

    _resolveRoute();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _clock?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resolveRoute() async {
    final route = await _routeResolver.resolve(widget.bus);
    if (!mounted) return;

    setState(() {
      _isResolvingRoute = false;
      _routeWarning = route.warning;
      if (route.stops.length >= 2) {
        _routeStops = route.stops;
        _tracker = RouteProgressTracker(route.points);
        final bus = _latestBusLatLng;
        if (bus != null) _progress = _tracker!.update(bus);
      }
    });
    _scrollToBusOnce();
  }

  void _onLocation(Map<String, dynamic> data) {
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final position = LatLng(lat, lng);
    setState(() {
      _latestBusLatLng = position;
      _lastUpdate = DateTime.tryParse(data['updatedAt']?.toString() ?? '')?.toLocal() ?? DateTime.now();
      _progress = _tracker?.update(position);
    });
    _scrollToBusOnce();
  }

  /// Scrolls the timeline so the bus is visible, the first time it is placed.
  void _scrollToBusOnce() {
    final progress = _progress;
    if (_hasScrolledToBus || progress == null) return;
    _hasScrolledToBus = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final stopIndex = progress.atStopIndex ?? progress.fromIndex;
      final target = (stopIndex * RouteTimelineTile.height - RouteTimelineTile.height)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
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

  /// Timeline rows: the resolved stops when the route has positions,
  /// otherwise just the stop names (without a live bus).
  List<String> get _rowNames =>
      _routeStops.length >= 2 ? [for (final stop in _routeStops) stop.name] : _stopNames;

  bool get _isStale =>
      _lastUpdate != null && DateTime.now().difference(_lastUpdate!) > _staleAfter;

  RouteTimelineTile _buildTile(int index, List<String> names) {
    final progress = _progress;
    var state = TimelineStopState.upcoming;
    var connectorProgress = 0.0;
    double? busFraction;

    if (progress != null) {
      final atStop = progress.atStopIndex;
      if (atStop != null) {
        if (index < atStop) {
          state = TimelineStopState.passed;
          connectorProgress = 1;
        } else if (index == atStop) {
          state = TimelineStopState.current;
        } else if (index == atStop + 1) {
          state = TimelineStopState.next;
        }
      } else {
        if (index <= progress.fromIndex) state = TimelineStopState.passed;
        if (index == progress.toIndex) state = TimelineStopState.next;
        if (index < progress.fromIndex) connectorProgress = 1;
        if (index == progress.fromIndex) {
          connectorProgress = progress.fraction;
          busFraction = progress.fraction;
        }
      }
    }

    return RouteTimelineTile(
      name: names[index],
      index: index,
      totalStops: names.length,
      state: state,
      connectorProgress: connectorProgress,
      busFraction: busFraction,
      busIsStale: _isStale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final names = _rowNames;

    return Scaffold(
      body: GlowBackdrop(
        style: GlowStyle.top,
        intensity: 0.4,
        child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  RoundIconButton(
                    icon: Icons.arrow_back,
                    tooltip: 'Back',
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.bus.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.heading.copyWith(fontSize: 22),
                        ),
                        Text('Live route - ${widget.bus.number}', style: AppText.secondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _StatusCard(
              liveText: _liveText(),
              locationText: _locationText(names),
              warning: _warningText(),
              isLive: _lastUpdate != null && !_isStale,
              isLoading: _isResolvingRoute,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  const Expanded(child: Text('Route stops', style: AppText.heading)),
                  Pill('${names.length} stops'),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 12, 16, 24),
                itemExtent: RouteTimelineTile.height,
                itemCount: names.length,
                itemBuilder: (context, index) => _buildTile(index, names),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: ElevatedButton.icon(
                onPressed: _openInGoogleMaps,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Go to Google Maps'),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  String _liveText() {
    final last = _lastUpdate;
    if (last == null) return 'Waiting for live location…';
    final ago = DateTime.now().difference(last);
    final agoText = ago.inSeconds < 60
        ? '${ago.inSeconds.clamp(0, 59)}s ago'
        : ago.inMinutes < 60
            ? '${ago.inMinutes} min ago'
            : '${ago.inHours} h ago';
    return _isStale ? 'Last seen $agoText' : 'Live · updated $agoText';
  }

  String? _locationText(List<String> names) {
    final progress = _progress;
    if (progress == null) return null;
    final atStop = progress.atStopIndex;
    if (atStop != null) return 'At ${names[atStop]}';
    return 'Between ${names[progress.fromIndex]} and ${names[progress.toIndex]}';
  }

  String? _warningText() {
    if (_routeWarning != null) return _routeWarning;
    final progress = _progress;
    if (progress != null && progress.offRouteMetres > _offRouteMetres) {
      return 'The bus seems to be off its usual route.';
    }
    if (!_isResolvingRoute && _tracker == null && _latestBusLatLng != null) {
      return "The bus's live position can't be shown for this route.";
    }
    return null;
  }
}

/// Live status above the timeline: freshness, where the bus is, and warnings.
class _StatusCard extends StatelessWidget {
  final String liveText;
  final String? locationText;
  final String? warning;
  final bool isLive;
  final bool isLoading;

  const _StatusCard({
    required this.liveText,
    required this.locationText,
    required this.warning,
    required this.isLive,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LiveDot(isLive: isLive),
                const SizedBox(width: 10),
                Expanded(child: Text(liveText, style: AppText.secondary.copyWith(color: AppColors.text))),
                if (isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (locationText == null)
              Text('Locating bus…', style: AppText.title.copyWith(fontSize: 24, color: AppColors.faint))
            else
              GradientHeadline(
                locationText!,
                textAlign: TextAlign.start,
                style: AppText.title.copyWith(fontSize: 24),
              ),
            if (warning != null) ...[
              const SizedBox(height: 10),
              Text(warning!, style: AppText.secondary.copyWith(color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

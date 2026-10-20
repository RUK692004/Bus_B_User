import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/bus_info.dart';
import 'api_client.dart';

/// Service responsible for querying bus search, trips, route coordinates,
/// and subscribing to live bus location telemetry via WebSocket.
class BusService {
  final ApiClient apiClient;
  String _prefix;

  BusService({
    ApiClient? apiClient,
    String defaultPrefix = '/api/buses',
  })  : apiClient = apiClient ?? ApiClient(),
        _prefix = defaultPrefix;

  /// Converts an HTTP base URL to its corresponding WebSocket URL.
  static String defaultWsUrl({String? baseUrl}) {
    const envWs = String.fromEnvironment('WS_BASE_URL');
    if (envWs.isNotEmpty) return envWs;

    final httpUrl = baseUrl ?? ApiClient.defaultBaseUrl;
    if (httpUrl.startsWith('https://')) {
      return httpUrl.replaceFirst('https://', 'wss://');
    } else if (httpUrl.startsWith('http://')) {
      return httpUrl.replaceFirst('http://', 'ws://');
    }
    return 'ws://localhost:5000';
  }

  Future<dynamic> _get(
    String subPath, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final path = '$_prefix$subPath';
    try {
      return await apiClient.get(path, queryParameters: queryParameters);
    } on ApiException catch (e) {
      // If endpoint route is not found, attempt alternate API prefix (/api/buses vs /api/v1/buses)
      if (e.statusCode == 404 &&
          (e.message.contains('Route not found') ||
              e.message.contains('Cannot GET') ||
              e.message.contains('Not Found'))) {
        final altPrefix = _prefix == '/api/buses' ? '/api/v1/buses' : '/api/buses';
        final altPath = '$altPrefix$subPath';
        try {
          final res = await apiClient.get(altPath, queryParameters: queryParameters);
          _prefix = altPrefix;
          return res;
        } catch (_) {
          rethrow;
        }
      }
      rethrow;
    }
  }

  /// Fetches live buses located within [radiusMeters] of the specified coordinates.
  Future<List<BusInfo>> getNearbyBuses({
    required double lat,
    required double lng,
    double radiusMeters = 2000,
  }) async {
    final response = await _get(
      '/nearby',
      queryParameters: {
        'lat': lat,
        'lng': lng,
        'radius': radiusMeters,
      },
    );

    if (response is Map<String, dynamic> && response.containsKey('buses')) {
      final list = response['buses'] as List? ?? [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => BusInfo.fromJson(item))
          .toList();
    }
    return const [];
  }

  /// Searches for a bus by its identifier or number. Returns null if not found.
  Future<BusInfo?> searchBusByNumber(String number) async {
    try {
      final response = await _get(
        '/search',
        queryParameters: {'number': number.trim()},
      );

      if (response is Map<String, dynamic> && response.containsKey('bus')) {
        final busMap = response['bus'];
        if (busMap is Map<String, dynamic>) {
          return BusInfo.fromJson(busMap);
        }
      }
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  /// Searches for bus trips running from [from] to [to].
  Future<List<BusInfo>> searchTrips({
    required String from,
    required String to,
  }) async {
    final response = await _get(
      '/trips',
      queryParameters: {
        'from': from.trim(),
        'to': to.trim(),
      },
    );

    if (response is Map<String, dynamic> && response.containsKey('buses')) {
      final list = response['buses'] as List? ?? [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => BusInfo.fromJson(item))
          .toList();
    }
    return const [];
  }

  /// Fetches saved route coordinates for the given bus ID.
  Future<List<Map<String, dynamic>>> getBusRoute(String busId) async {
    final response = await _get('/$busId/route');
    if (response is Map<String, dynamic> && response.containsKey('route')) {
      final routeList = response['route'] as List? ?? [];
      return routeList.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  /// Subscribes to real-time location telemetry for [busId] via WebSocket.
  /// Sends `{"type": "subscribe", "busId": busId}` on connection,
  /// parses `location_update` events, and sends `unsubscribe` on cancellation.
  ///
  /// When the connection drops, it reconnects with exponential backoff
  /// (starting at [initialRetryDelay], capped at [maxRetryDelay]) until the
  /// stream is cancelled. New connections are opened with [connect]
  /// (defaults to [WebSocketChannel.connect]). If [channel] is supplied
  /// without [connect], it is used once and the stream closes when it ends.
  Stream<Map<String, dynamic>> subscribeBusLocation({
    required String busId,
    WebSocketChannel? channel,
    String? wsUrl,
    WebSocketChannel Function(Uri uri)? connect,
    Duration initialRetryDelay = const Duration(seconds: 1),
    Duration maxRetryDelay = const Duration(seconds: 30),
  }) {
    return _BusLocationSubscription(
      busId: busId,
      uri: Uri.parse(wsUrl ?? defaultWsUrl(baseUrl: apiClient.baseUrl)),
      initialChannel: channel,
      connect: connect,
      initialRetryDelay: initialRetryDelay,
      maxRetryDelay: maxRetryDelay,
    ).stream;
  }
}

/// One live-location subscription, including its reconnect state.
class _BusLocationSubscription {
  final String busId;
  final Uri uri;
  final WebSocketChannel Function(Uri uri) _connect;
  final bool _canReconnect;
  final Duration initialRetryDelay;
  final Duration maxRetryDelay;

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  Timer? _retryTimer;
  late Duration _retryDelay = initialRetryDelay;
  bool _cancelled = false;

  _BusLocationSubscription({
    required this.busId,
    required this.uri,
    required WebSocketChannel? initialChannel,
    required WebSocketChannel Function(Uri uri)? connect,
    required this.initialRetryDelay,
    required this.maxRetryDelay,
  })  : _connect = connect ?? WebSocketChannel.connect,
        // An injected channel with no way to open another one cannot reconnect.
        _canReconnect = initialChannel == null || connect != null {
    _controller.onCancel = _cancel;
    _open(initialChannel);
  }

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void _open(WebSocketChannel? existing) {
    final WebSocketChannel channel;
    try {
      channel = existing ?? _connect(uri);
      channel.sink.add(jsonEncode({'type': 'subscribe', 'busId': busId}));
    } catch (e) {
      debugPrint('[BusService] Could not open live location socket for bus $busId: $e');
      _onConnectionLost();
      return;
    }

    _channel = channel;
    _channelSub = channel.stream.listen(
      _onMessage,
      onError: (Object e) {
        debugPrint('[BusService] Live location socket error for bus $busId: $e');
      },
      onDone: _onConnectionLost,
    );
  }

  void _onMessage(dynamic data) {
    // Any message means the connection is healthy again.
    _retryDelay = initialRetryDelay;

    final Object? decoded;
    try {
      decoded = jsonDecode(data.toString());
    } on FormatException catch (e) {
      debugPrint('[BusService] Ignoring malformed live location message for bus $busId: $e');
      return;
    }

    if (decoded is Map<String, dynamic>) {
      final type = decoded['type'] ?? decoded['event'];
      if (type == 'location_update' ||
          (decoded.containsKey('lat') && decoded.containsKey('lng')) ||
          (decoded.containsKey('latitude') && decoded.containsKey('longitude'))) {
        _controller.add(decoded);
      }
    }
  }

  void _onConnectionLost() {
    _channelSub?.cancel();
    _channelSub = null;
    _channel = null;
    if (_cancelled) return;

    if (!_canReconnect) {
      _controller.close();
      return;
    }

    final delay = _retryDelay;
    final doubled = _retryDelay * 2;
    _retryDelay = doubled > maxRetryDelay ? maxRetryDelay : doubled;
    debugPrint('[BusService] Live location socket for bus $busId closed; reconnecting in ${delay.inMilliseconds} ms');
    _retryTimer = Timer(delay, () {
      if (!_cancelled) _open(null);
    });
  }

  Future<void> _cancel() async {
    _cancelled = true;
    _retryTimer?.cancel();

    final channel = _channel;
    if (channel != null) {
      try {
        channel.sink.add(jsonEncode({'type': 'unsubscribe', 'busId': busId}));
      } catch (e) {
        debugPrint('[BusService] Could not send unsubscribe for bus $busId: $e');
      }
      await _channelSub?.cancel();
      await channel.sink.close();
    }
  }
}

import 'dart:async';
import 'dart:convert';
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
  Stream<Map<String, dynamic>> subscribeBusLocation({
    required String busId,
    WebSocketChannel? channel,
    String? wsUrl,
  }) {
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    WebSocketChannel? activeChannel = channel;
    StreamSubscription? channelSub;

    try {
      final targetUrl = wsUrl ?? defaultWsUrl(baseUrl: apiClient.baseUrl);
      activeChannel ??= WebSocketChannel.connect(Uri.parse(targetUrl));

      // Subscribe to the target bus
      activeChannel.sink.add(jsonEncode({
        'type': 'subscribe',
        'busId': busId,
      }));

      channelSub = activeChannel.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data.toString());
            if (decoded is Map<String, dynamic>) {
              final type = decoded['type'] ?? decoded['event'];
              if (type == 'location_update' ||
                  (decoded.containsKey('lat') && decoded.containsKey('lng')) ||
                  (decoded.containsKey('latitude') && decoded.containsKey('longitude'))) {
                controller.add(decoded);
              }
            }
          } catch (_) {
            // Ignore malformed message without crashing
          }
        },
        onError: (err) {
          // Gracefully absorb connection errors
        },
        onDone: () {
          if (!controller.isClosed) {
            controller.close();
          }
        },
      );
    } catch (_) {
      // Handled safely without crashing
    }

    controller.onCancel = () {
      try {
        activeChannel?.sink.add(jsonEncode({
          'type': 'unsubscribe',
          'busId': busId,
        }));
      } catch (_) {}
      channelSub?.cancel();
      activeChannel?.sink.close();
    };

    return controller.stream;
  }
}

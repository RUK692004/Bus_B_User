import '../models/bus_info.dart';
import 'api_client.dart';

/// Service responsible for querying bus search, trips, and nearby buses from backend REST API.
class BusService {
  final ApiClient apiClient;
  String _prefix;

  BusService({
    ApiClient? apiClient,
    String defaultPrefix = '/api/buses',
  })  : apiClient = apiClient ?? ApiClient(),
        _prefix = defaultPrefix;

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
}

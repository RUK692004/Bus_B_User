import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Custom exception representing an API error or network failure.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic data;

  const ApiException({
    required this.message,
    this.statusCode,
    this.data,
  });

  @override
  String toString() {
    if (statusCode != null) {
      return 'ApiException($statusCode): $message';
    }
    return 'ApiException: $message';
  }
}

/// Reusable HTTP client for communicating with the BusBee backend.
class ApiClient {
  final String baseUrl;
  final http.Client _client;
  final bool _isClientOwned;
  final Future<String?> Function()? tokenProvider;
  final Duration timeout;

  ApiClient({
    String? baseUrl,
    http.Client? client,
    this.tokenProvider,
    this.timeout = const Duration(seconds: 15),
  })  : baseUrl = _normalizeBaseUrl(baseUrl ?? defaultBaseUrl),
        _client = client ?? http.Client(),
        _isClientOwned = client == null;

  /// Determines default base URL based on environment definitions or host platform.
  static String get defaultBaseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:5000';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:5000';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      default:
        return 'http://localhost:5000';
    }
  }

  static String _normalizeBaseUrl(String url) {
    if (url.endsWith('/')) {
      return url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Constructs the full URI for the given endpoint and query parameters.
  Uri _buildUri(String path, [Map<String, dynamic>? queryParameters]) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final fullUrlString = '$baseUrl$cleanPath';

    Map<String, String>? queryMap;
    if (queryParameters != null && queryParameters.isNotEmpty) {
      queryMap = {};
      queryParameters.forEach((key, value) {
        if (value != null) {
          queryMap![key] = value.toString();
        }
      });
    }

    final parsedUri = Uri.parse(fullUrlString);
    if (queryMap != null && queryMap.isNotEmpty) {
      return parsedUri.replace(
        queryParameters: {
          ...parsedUri.queryParameters,
          ...queryMap,
        },
      );
    }
    return parsedUri;
  }

  /// Builds request headers including JSON content types and auth bearer tokens if requested.
  Future<Map<String, String>> _buildHeaders({
    Map<String, String>? extraHeaders,
    bool requiresAuth = false,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };

    if (requiresAuth) {
      final token = await tokenProvider?.call();
      if (token == null || token.trim().isEmpty) {
        throw const ApiException(
          message: 'Authentication required. No access token available.',
          statusCode: 401,
        );
      }
      headers['Authorization'] = 'Bearer $token';
    }

    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }

    return headers;
  }

  /// Sends a GET request.
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final reqHeaders = await _buildHeaders(
      extraHeaders: headers,
      requiresAuth: requiresAuth,
    );

    return _execute(() => _client.get(uri, headers: reqHeaders));
  }

  /// Sends a POST request.
  Future<dynamic> post(
    String path, {
    Map<String, String>? headers,
    dynamic body,
    bool requiresAuth = false,
  }) async {
    final uri = _buildUri(path);
    final reqHeaders = await _buildHeaders(
      extraHeaders: headers,
      requiresAuth: requiresAuth,
    );
    final encodedBody = _encodeBody(body);

    return _execute(() => _client.post(uri, headers: reqHeaders, body: encodedBody));
  }

  /// Sends a PUT request.
  Future<dynamic> put(
    String path, {
    Map<String, String>? headers,
    dynamic body,
    bool requiresAuth = false,
  }) async {
    final uri = _buildUri(path);
    final reqHeaders = await _buildHeaders(
      extraHeaders: headers,
      requiresAuth: requiresAuth,
    );
    final encodedBody = _encodeBody(body);

    return _execute(() => _client.put(uri, headers: reqHeaders, body: encodedBody));
  }

  /// Sends a DELETE request.
  Future<dynamic> delete(
    String path, {
    Map<String, String>? headers,
    dynamic body,
    bool requiresAuth = false,
  }) async {
    final uri = _buildUri(path);
    final reqHeaders = await _buildHeaders(
      extraHeaders: headers,
      requiresAuth: requiresAuth,
    );
    final encodedBody = _encodeBody(body);

    return _execute(() => _client.delete(uri, headers: reqHeaders, body: encodedBody));
  }

  String? _encodeBody(dynamic body) {
    if (body == null) return null;
    if (body is String) return body;
    return jsonEncode(body);
  }

  /// Executes an HTTP request with timeout and standardized error handling.
  Future<dynamic> _execute(Future<http.Response> Function() requestFn) async {
    try {
      final response = await requestFn().timeout(timeout);
      return _handleResponse(response);
    } on TimeoutException {
      throw const ApiException(
        message: 'Request timed out. Please check your network connection and try again.',
      );
    } on SocketException {
      throw const ApiException(
        message: 'Network unreachable. Please check your internet connection.',
      );
    } on http.ClientException catch (e) {
      throw ApiException(
        message: 'Network connection failed: ${e.message}',
      );
    } on FormatException {
      throw const ApiException(
        message: 'Invalid response format received from server.',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        message: 'Unexpected network error: $e',
      );
    }
  }

  /// Decodes and validates response body. Throws [ApiException] for status >= 400.
  dynamic _handleResponse(http.Response response) {
    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }
    }

    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
    if (isSuccess) {
      return decoded ?? <String, dynamic>{};
    }

    String message = 'Request failed with status ${response.statusCode}.';
    if (decoded is Map) {
      final serverMessage = decoded['message'] ?? decoded['error'];
      if (serverMessage != null && serverMessage.toString().trim().isNotEmpty) {
        message = serverMessage.toString();
      }
    }

    throw ApiException(
      message: message,
      statusCode: response.statusCode,
      data: decoded,
    );
  }

  /// Closes the client if it was created internally.
  void close() {
    if (_isClientOwned) {
      _client.close();
    }
  }
}

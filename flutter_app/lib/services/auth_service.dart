import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_response.dart';
import '../models/user_model.dart';
import 'api_client.dart';

export '../models/auth_response.dart';
export '../models/user_model.dart';
export 'api_client.dart';

/// Service responsible for user authentication and secure token management.
class AuthService {
  static const String accessTokenKey = 'auth_access_token';
  static const String refreshTokenKey = 'auth_refresh_token';

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final ApiClient apiClient;
  final FlutterSecureStorage secureStorage;

  AuthService({
    ApiClient? apiClient,
    FlutterSecureStorage? secureStorage,
  })  : secureStorage = secureStorage ?? _defaultStorage,
        apiClient = apiClient ??
            ApiClient(
              tokenProvider: () async {
                final storage = secureStorage ?? _defaultStorage;
                return await storage.read(key: accessTokenKey);
              },
            );

  /// Registers a new user with name, email, password, and optional role.
  /// On success, securely saves the access token and returns the [AuthResponse].
  Future<AuthResponse> signUp({
    required String name,
    required String email,
    required String password,
    String role = 'user',
  }) async {
    final response = await apiClient.post(
      '/api/auth/signup',
      body: {
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
        'role': role,
      },
    );

    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid response format from server.');
    }

    final authResponse = AuthResponse.fromJson(response);
    if (authResponse.token.isEmpty) {
      throw const ApiException(message: 'Authentication token missing from response.');
    }

    await saveTokens(
      accessToken: authResponse.token,
      refreshToken: authResponse.refreshToken,
    );

    return authResponse;
  }

  /// Authenticates an existing user with email and password.
  /// On success, securely saves the access token and returns the [AuthResponse].
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await apiClient.post(
      '/api/auth/login',
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
      },
    );

    if (response is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid response format from server.');
    }

    final authResponse = AuthResponse.fromJson(response);
    if (authResponse.token.isEmpty) {
      throw const ApiException(message: 'Authentication token missing from response.');
    }

    await saveTokens(
      accessToken: authResponse.token,
      refreshToken: authResponse.refreshToken,
    );

    return authResponse;
  }

  /// Logs the user out by clearing stored credentials and tokens.
  Future<void> logout() async {
    await clearTokens();
  }

  /// Retrieves the stored access token, or null if no token exists.
  Future<String?> getToken() async {
    return await secureStorage.read(key: accessTokenKey);
  }

  /// Retrieves the stored refresh token if available, or null.
  Future<String?> getRefreshToken() async {
    return await secureStorage.read(key: refreshTokenKey);
  }

  /// Saves the given access token and optional refresh token securely.
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await secureStorage.write(key: accessTokenKey, value: accessToken);
    if (refreshToken != null && refreshToken.trim().isNotEmpty) {
      await secureStorage.write(key: refreshTokenKey, value: refreshToken);
    }
  }

  /// Clears stored access and refresh tokens from secure storage.
  Future<void> clearTokens() async {
    await secureStorage.delete(key: accessTokenKey);
    await secureStorage.delete(key: refreshTokenKey);
  }

  /// Fetches the authenticated user profile using the stored access token.
  Future<UserModel> getCurrentUser() async {
    final response = await apiClient.get(
      '/api/auth/me',
      requiresAuth: true,
    );

    if (response is! Map<String, dynamic> || !response.containsKey('user')) {
      throw const ApiException(message: 'Failed to retrieve user profile.');
    }

    final userJson = response['user'];
    if (userJson is! Map<String, dynamic>) {
      throw const ApiException(message: 'Invalid user profile data.');
    }

    return UserModel.fromJson(userJson);
  }
}

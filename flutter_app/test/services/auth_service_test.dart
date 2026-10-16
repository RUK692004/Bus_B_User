import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_app/services/auth_service.dart';
import '../test_helpers.dart';

void main() {
  group('AuthService', () {
    late FakeSecureStorage fakeStorage;

    setUp(() {
      fakeStorage = FakeSecureStorage();
    });

    test('signUp succeeds, saves token, and returns AuthResponse', () async {
      final mockHttp = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/auth/signup');
        final body = jsonDecode(request.body);
        expect(body['name'], 'Alice');
        expect(body['email'], 'alice@example.com');
        expect(body['password'], 'secret123');

        return http.Response(
          jsonEncode({
            'token': 'jwt_signup_token',
            'user': {
              'id': 'user-uuid-1',
              'name': 'Alice',
              'email': 'alice@example.com',
              'role': 'user',
            },
          }),
          201,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final authService = AuthService(apiClient: apiClient, secureStorage: fakeStorage);

      final result = await authService.signUp(
        name: 'Alice',
        email: 'alice@example.com',
        password: 'secret123',
      );

      expect(result.token, 'jwt_signup_token');
      expect(result.user.name, 'Alice');
      expect(result.user.email, 'alice@example.com');

      // Verify token was saved in secure storage
      final storedToken = await authService.getToken();
      expect(storedToken, 'jwt_signup_token');
    });

    test('signUp failure throws ApiException and does NOT save token', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'An account with this email already exists.'}),
          409,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final authService = AuthService(apiClient: apiClient, secureStorage: fakeStorage);

      expect(
        () => authService.signUp(
          name: 'Alice',
          email: 'alice@example.com',
          password: 'secret123',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', 'An account with this email already exists.'),
        ),
      );

      final storedToken = await authService.getToken();
      expect(storedToken, isNull);
    });

    test('login succeeds, saves token, and returns AuthResponse', () async {
      final mockHttp = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/auth/login');
        final body = jsonDecode(request.body);
        expect(body['email'], 'bob@example.com');
        expect(body['password'], 'mypassword');

        return http.Response(
          jsonEncode({
            'token': 'jwt_login_token',
            'user': {
              'id': 'user-uuid-2',
              'name': 'Bob',
              'email': 'bob@example.com',
              'role': 'user',
            },
          }),
          200,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final authService = AuthService(apiClient: apiClient, secureStorage: fakeStorage);

      final result = await authService.login(
        email: 'bob@example.com',
        password: 'mypassword',
      );

      expect(result.token, 'jwt_login_token');
      expect(result.user.id, 'user-uuid-2');
      expect(result.user.email, 'bob@example.com');

      final storedToken = await authService.getToken();
      expect(storedToken, 'jwt_login_token');
    });

    test('login failure throws ApiException and does NOT save token', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Invalid email or password.'}),
          401,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final authService = AuthService(apiClient: apiClient, secureStorage: fakeStorage);

      expect(
        () => authService.login(
          email: 'bob@example.com',
          password: 'wrongpassword',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'Invalid email or password.'),
        ),
      );

      final storedToken = await authService.getToken();
      expect(storedToken, isNull);
    });

    test('logout clears stored tokens', () async {
      final apiClient = ApiClient(baseUrl: 'http://localhost:5000');
      final authService = AuthService(apiClient: apiClient, secureStorage: fakeStorage);

      await authService.saveTokens(
        accessToken: 'valid_token_xyz',
        refreshToken: 'refresh_token_xyz',
      );

      expect(await authService.getToken(), 'valid_token_xyz');
      expect(await authService.getRefreshToken(), 'refresh_token_xyz');

      await authService.logout();

      expect(await authService.getToken(), isNull);
      expect(await authService.getRefreshToken(), isNull);
    });

    test('getCurrentUser fetches profile with Bearer token', () async {
      await fakeStorage.write(key: AuthService.accessTokenKey, value: 'active_session_token');

      final mockHttp = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/auth/me');
        expect(request.headers['Authorization'], 'Bearer active_session_token');

        return http.Response(
          jsonEncode({
            'user': {
              'id': 'profile-id-123',
              'name': 'Charlie',
              'email': 'charlie@example.com',
              'role': 'user',
            },
          }),
          200,
        );
      });

      final apiClient = ApiClient(
        baseUrl: 'http://localhost:5000',
        client: mockHttp,
        tokenProvider: () => fakeStorage.read(key: AuthService.accessTokenKey),
      );
      final authService = AuthService(apiClient: apiClient, secureStorage: fakeStorage);

      final user = await authService.getCurrentUser();
      expect(user.id, 'profile-id-123');
      expect(user.name, 'Charlie');
      expect(user.email, 'charlie@example.com');
    });
  });
}

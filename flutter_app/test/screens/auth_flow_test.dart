import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_app/main.dart';
import 'package:flutter_app/screens/bus_search_screen.dart';
import 'package:flutter_app/screens/login_screen.dart';
import 'package:flutter_app/screens/settings_screen.dart';
import 'package:flutter_app/screens/sign_up_screen.dart';
import 'package:flutter_app/services/auth_service.dart';
import '../test_helpers.dart';

void main() {
  group('determineInitialScreen (Startup Session Verification)', () {
    late FakeSecureStorage fakeStorage;

    setUp(() {
      fakeStorage = FakeSecureStorage();
    });

    test('returns BusSearchScreen when valid token exists and /api/auth/me succeeds', () async {
      await fakeStorage.write(key: AuthService.accessTokenKey, value: 'valid_jwt_token');

      final mockHttp = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'user-1',
                'name': 'Test User',
                'email': 'user@example.com',
                'role': 'user',
              }
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(
        baseUrl: 'http://localhost:5000',
        client: mockHttp,
        tokenProvider: () => fakeStorage.read(key: AuthService.accessTokenKey),
      );
      final authService = AuthService(apiClient: apiClient, secureStorage: fakeStorage);

      final screen = await determineInitialScreen(authService: authService);
      expect(screen, isA<BusSearchScreen>());
    });

    test('clears token and returns LoginScreen when token is expired/invalid (401)', () async {
      await fakeStorage.write(key: AuthService.accessTokenKey, value: 'expired_token');

      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Token has expired.'}),
          401,
        );
      });

      final apiClient = ApiClient(
        baseUrl: 'http://localhost:5000',
        client: mockHttp,
        tokenProvider: () => fakeStorage.read(key: AuthService.accessTokenKey),
      );
      final authService = AuthService(apiClient: apiClient, secureStorage: fakeStorage);

      final screen = await determineInitialScreen(authService: authService);
      expect(screen, isA<LoginScreen>());
      expect(await fakeStorage.read(key: AuthService.accessTokenKey), isNull);
    });

    test('returns LoginScreen when no token is stored', () async {
      final authService = AuthService(secureStorage: fakeStorage);

      final screen = await determineInitialScreen(authService: authService);
      expect(screen, isA<LoginScreen>());
    });
  });

  group('LoginScreen Widget Tests', () {
    late FakeSecureStorage fakeStorage;

    setUp(() {
      fakeStorage = FakeSecureStorage();
    });

    testWidgets('shows error when fields are empty', (tester) async {
      final authService = AuthService(secureStorage: fakeStorage);

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(authService: authService),
        ),
      );

      // Tap Login button with empty inputs
      await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter email and password.'), findsOneWidget);
    });

    testWidgets('displays backend error message on 401 response and does not navigate', (tester) async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Invalid email or password.'}),
          401,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final authService = AuthService(apiClient: apiClient, secureStorage: fakeStorage);

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(authService: authService),
        ),
      );

      // Enter email and password
      await tester.enterText(find.byType(TextField).at(0), 'wrong@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'wrongpass');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid email or password.'), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(BusSearchScreen), findsNothing);
    });

    testWidgets('successful login navigates to BusSearchScreen and stores token', (tester) async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'token': 'mocked_jwt_token_123',
            'user': {
              'id': 'user-1',
              'name': 'Valid User',
              'email': 'valid@example.com',
              'role': 'user',
            }
          }),
          200,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final authService = AuthService(apiClient: apiClient, secureStorage: fakeStorage);

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(authService: authService),
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'valid@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'password123');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
      await tester.pumpAndSettle();

      expect(find.byType(BusSearchScreen), findsOneWidget);
      expect(await fakeStorage.read(key: AuthService.accessTokenKey), 'mocked_jwt_token_123');
    });
  });

  group('SignUpScreen Widget Tests', () {
    late FakeSecureStorage fakeStorage;

    setUp(() {
      fakeStorage = FakeSecureStorage();
    });

    testWidgets('displays form validation errors for invalid input', (tester) async {
      final authService = AuthService(secureStorage: fakeStorage);

      await tester.pumpWidget(
        MaterialApp(
          home: SignUpScreen(authService: authService),
        ),
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign Up'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    });

    testWidgets('displays error message from backend when signup fails', (tester) async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'An account with this email already exists.'}),
          409,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final authService = AuthService(apiClient: apiClient, secureStorage: fakeStorage);

      await tester.pumpWidget(
        MaterialApp(
          home: SignUpScreen(authService: authService),
        ),
      );

      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), 'Jane Doe');
      await tester.enterText(textFields.at(1), 'exists@example.com');
      await tester.enterText(textFields.at(2), 'secure123');
      await tester.enterText(textFields.at(3), 'secure123');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign Up'));
      await tester.pumpAndSettle();

      expect(find.text('An account with this email already exists.'), findsOneWidget);
      expect(find.byType(SignUpScreen), findsOneWidget);
    });

    testWidgets('successful signup navigates to LoginScreen', (tester) async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'token': 'signup_token_456',
            'user': {
              'id': 'user-2',
              'name': 'Jane Doe',
              'email': 'jane@example.com',
              'role': 'user',
            }
          }),
          201,
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final authService = AuthService(apiClient: apiClient, secureStorage: fakeStorage);

      await tester.pumpWidget(
        MaterialApp(
          home: SignUpScreen(authService: authService),
        ),
      );

      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), 'Jane Doe');
      await tester.enterText(textFields.at(1), 'jane@example.com');
      await tester.enterText(textFields.at(2), 'secure123');
      await tester.enterText(textFields.at(3), 'secure123');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign Up'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('SettingsScreen Widget Tests', () {
    late FakeSecureStorage fakeStorage;

    setUp(() {
      fakeStorage = FakeSecureStorage();
    });

    testWidgets('tapping Logout clears stored tokens and navigates to LoginScreen', (tester) async {
      await fakeStorage.write(key: AuthService.accessTokenKey, value: 'active_session');
      final authService = AuthService(secureStorage: fakeStorage);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(authService: authService),
        ),
      );

      expect(find.text('Logout'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Logout'));
      await tester.pumpAndSettle();

      // Token should now be removed from secure storage
      expect(await fakeStorage.read(key: AuthService.accessTokenKey), isNull);
      // Navigation should be to LoginScreen
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_app/services/api_client.dart';

void main() {
  group('ApiClient', () {
    test('normalizes baseUrl by stripping trailing slash', () {
      final client = ApiClient(baseUrl: 'http://localhost:5000/');
      expect(client.baseUrl, 'http://localhost:5000');
    });

    test('performs GET request with query parameters and parses JSON', () async {
      final mockHttp = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/buses/search');
        expect(request.url.queryParameters['number'], '101');
        return http.Response(jsonEncode({'success': true}), 200);
      });

      final client = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final response = await client.get('/api/buses/search', queryParameters: {'number': '101'});

      expect(response, isA<Map<String, dynamic>>());
      expect(response['success'], true);
    });

    test('performs POST request and encodes body', () async {
      final mockHttp = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/auth/login');
        expect(request.headers['Content-Type'], contains('application/json'));
        final body = jsonDecode(request.body);
        expect(body['email'], 'test@example.com');
        return http.Response(jsonEncode({'token': 'jwt_123'}), 200);
      });

      final client = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);
      final response = await client.post('/api/auth/login', body: {'email': 'test@example.com'});

      expect(response['token'], 'jwt_123');
    });

    test('attaches Authorization header when requiresAuth is true', () async {
      final mockHttp = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer secret_token_abc');
        return http.Response(jsonEncode({'user': {'id': '1'}}), 200);
      });

      final client = ApiClient(
        baseUrl: 'http://localhost:5000',
        client: mockHttp,
        tokenProvider: () async => 'secret_token_abc',
      );

      final response = await client.get('/api/auth/me', requiresAuth: true);
      expect(response['user']['id'], '1');
    });

    test('throws ApiException when requiresAuth is true and token is missing', () async {
      final mockHttp = MockClient((request) async => http.Response('{}', 200));

      final client = ApiClient(
        baseUrl: 'http://localhost:5000',
        client: mockHttp,
        tokenProvider: () async => null,
      );

      expect(
        () => client.get('/api/auth/me', requiresAuth: true),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', contains('No access token available')),
        ),
      );
    });

    test('extracts backend error message on 400/401/409/500 responses', () async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Invalid email or password.'}),
          401,
        );
      });

      final client = ApiClient(baseUrl: 'http://localhost:5000', client: mockHttp);

      expect(
        () => client.post('/api/auth/login', body: {'email': 'bad@example.com'}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'Invalid email or password.'),
        ),
      );
    });

    test('handles timeout gracefully', () async {
      final mockHttp = MockClient((request) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response('{}', 200);
      });

      final client = ApiClient(
        baseUrl: 'http://localhost:5000',
        client: mockHttp,
        timeout: const Duration(milliseconds: 10),
      );

      expect(
        () => client.get('/api/health'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noahs_ark_app/services/api_exception.dart';
import 'package:noahs_ark_app/services/api_service.dart';

void main() {
  test('requests password reset with a normalized email', () async {
    final apiService = ApiService(
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/auth/password-reset/request');

        final body = jsonDecode(request.body) as Map<String, dynamic>;

        expect(body, {'email': 'test@example.com'});

        return http.Response(
          jsonEncode({
            'message':
                'If the email is registered, password reset instructions will be sent',
          }),
          202,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await apiService.requestPasswordReset(email: '  TEST@EXAMPLE.COM  ');
  });

  test('preserves password reset request API errors', () async {
    final apiService = ApiService(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Email delivery is not configured'}),
          503,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await expectLater(
      apiService.requestPasswordReset(email: 'test@example.com'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.message,
              'message',
              'Email delivery is not configured',
            ),
      ),
    );
  });

  test('confirms password reset with normalized token', () async {
    final apiService = ApiService(
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/auth/password-reset/confirm');

        final body = jsonDecode(request.body) as Map<String, dynamic>;

        expect(body, {'token': 'a' * 64, 'password': 'Replacement123'});

        return http.Response(
          jsonEncode({'reset': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await apiService.confirmPasswordReset(
      token: '  ${'A' * 64}  ',
      password: 'Replacement123',
    );
  });

  test('preserves invalid password reset token errors', () async {
    final apiService = ApiService(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Invalid or expired password reset token'}),
          400,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await expectLater(
      apiService.confirmPasswordReset(
        token: 'a' * 64,
        password: 'Replacement123',
      ),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 400)
            .having(
              (error) => error.message,
              'message',
              'Invalid or expired password reset token',
            ),
      ),
    );
  });

  test('rejects an invalid successful reset response', () async {
    final apiService = ApiService(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({'reset': false}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await expectLater(
      apiService.confirmPasswordReset(
        token: 'a' * 64,
        password: 'Replacement123',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

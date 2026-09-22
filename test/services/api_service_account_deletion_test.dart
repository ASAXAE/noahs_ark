import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noahs_ark_app/models/auth_tokens.dart';
import 'package:noahs_ark_app/services/api_exception.dart';
import 'package:noahs_ark_app/services/api_service.dart';
import 'package:noahs_ark_app/services/auth_session_storage.dart';
import 'package:noahs_ark_app/services/auth_token_coordinator.dart';

void main() {
  late AuthSessionStorage storage;
  late AuthTokenCoordinator coordinator;

  AuthTokens createTokens({
    required String accessToken,
    required String refreshToken,
  }) {
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      refreshTokenExpiresAt: DateTime.now().toUtc().add(
        const Duration(days: 30),
      ),
    );
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});

    storage = AuthSessionStorage(storage: const FlutterSecureStorage());

    coordinator = AuthTokenCoordinator(storage: storage);
  });

  test(
    'delete account preserves its password body while refreshing and retrying',
    () async {
      final original = createTokens(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
      );

      final replacement = createTokens(
        accessToken: 'new-access',
        refreshToken: 'new-refresh',
      );

      await storage.saveTokens(original);

      var deletionCallCount = 0;
      var refreshCallCount = 0;

      final client = MockClient((request) async {
        if (request.url.path == '/auth/account') {
          deletionCallCount++;

          expect(request.method, 'DELETE');

          expect(jsonDecode(request.body), {
            'password': 'Current Password 123',
          });

          if (request.headers['Authorization'] == 'Bearer old-access') {
            return http.Response('{}', 401);
          }

          expect(request.headers['Authorization'], 'Bearer new-access');

          return http.Response('', 204);
        }

        if (request.url.path == '/auth/token/refresh') {
          refreshCallCount++;

          expect(jsonDecode(request.body), {'refreshToken': 'old-refresh'});

          return http.Response(
            jsonEncode(replacement.toJson()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        throw StateError(
          'Unexpected request: '
          '${request.method} ${request.url}',
        );
      });

      final apiService = ApiService(
        httpClient: client,
        authTokenCoordinator: coordinator,
      );

      await apiService.deleteAccount(password: 'Current Password 123');

      expect(deletionCallCount, 2);
      expect(refreshCallCount, 1);

      final stored = await storage.readTokens();

      expect(stored?.accessToken, 'new-access');
      expect(stored?.refreshToken, 'new-refresh');
    },
  );

  test('delete account exposes an incorrect-password response', () async {
    await storage.saveTokens(
      createTokens(
        accessToken: 'current-access',
        refreshToken: 'current-refresh',
      ),
    );

    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/auth/account');

      return http.Response(
        jsonEncode({'message': 'Current password is incorrect'}),
        403,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiService = ApiService(
      httpClient: client,
      authTokenCoordinator: coordinator,
    );

    await expectLater(
      apiService.deleteAccount(password: 'WrongPassword456'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having(
              (error) => error.message,
              'message',
              'Current password is incorrect',
            ),
      ),
    );
  });
}

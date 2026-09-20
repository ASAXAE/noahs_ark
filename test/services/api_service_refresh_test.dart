import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noahs_ark_app/models/auth_tokens.dart';
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

  http.Response refreshResponse(AuthTokens tokens) {
    return http.Response(
      jsonEncode(tokens.toJson()),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    storage = AuthSessionStorage(storage: const FlutterSecureStorage());
    coordinator = AuthTokenCoordinator(storage: storage);
  });

  test(
    'refreshes after 401, stores the new tokens, and retries once',
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

      var thoughtCallCount = 0;
      var refreshCallCount = 0;

      final client = MockClient((request) async {
        if (request.url.path == '/thoughts') {
          thoughtCallCount++;
          final accessToken = request.headers['Authorization'];

          if (accessToken == 'Bearer old-access') {
            return http.Response('{}', 401);
          }

          expect(accessToken, 'Bearer new-access');
          return http.Response('[]', 200);
        }

        if (request.url.path == '/auth/token/refresh') {
          refreshCallCount++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['refreshToken'], 'old-refresh');
          return refreshResponse(replacement);
        }

        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      });

      final apiService = ApiService(
        httpClient: client,
        authTokenCoordinator: coordinator,
      );

      final thoughts = await apiService.fetchThoughts();

      expect(thoughts, isEmpty);
      expect(thoughtCallCount, 2);
      expect(refreshCallCount, 1);

      final stored = await storage.readTokens();
      expect(stored?.accessToken, 'new-access');
      expect(stored?.refreshToken, 'new-refresh');
    },
  );

  test('concurrent 401 responses share one refresh request', () async {
    final original = createTokens(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
    );
    final replacement = createTokens(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
    );
    await storage.saveTokens(original);

    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    var thoughtCallCount = 0;
    var refreshCallCount = 0;

    final client = MockClient((request) async {
      if (request.url.path == '/thoughts') {
        thoughtCallCount++;

        if (request.headers['Authorization'] == 'Bearer old-access') {
          return http.Response('{}', 401);
        }

        expect(request.headers['Authorization'], 'Bearer new-access');
        return http.Response('[]', 200);
      }

      if (request.url.path == '/auth/token/refresh') {
        refreshCallCount++;

        if (!refreshStarted.isCompleted) {
          refreshStarted.complete();
        }

        await releaseRefresh.future;
        return refreshResponse(replacement);
      }

      throw StateError('Unexpected request: ${request.method} ${request.url}');
    });

    final apiService = ApiService(
      httpClient: client,
      authTokenCoordinator: coordinator,
    );

    final first = apiService.fetchThoughts();
    final second = apiService.fetchThoughts();

    await refreshStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(refreshCallCount, 1);

    releaseRefresh.complete();

    final results = await Future.wait([first, second]);

    expect(results[0], isEmpty);
    expect(results[1], isEmpty);
    expect(thoughtCallCount, 4);
    expect(refreshCallCount, 1);
  });

  test('retries only once and clears a still-rejected session', () async {
    final original = createTokens(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
    );
    final replacement = createTokens(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
    );
    await storage.saveTokens(original);

    var thoughtCallCount = 0;
    var refreshCallCount = 0;

    final client = MockClient((request) async {
      if (request.url.path == '/thoughts') {
        thoughtCallCount++;
        return http.Response('{}', 401);
      }

      if (request.url.path == '/auth/token/refresh') {
        refreshCallCount++;
        return refreshResponse(replacement);
      }

      throw StateError('Unexpected request: ${request.method} ${request.url}');
    });

    final apiService = ApiService(
      httpClient: client,
      authTokenCoordinator: coordinator,
    );

    await expectLater(apiService.fetchThoughts(), throwsException);

    expect(thoughtCallCount, 2);
    expect(refreshCallCount, 1);
    expect(await storage.readTokens(), isNull);
  });

  test('logout sends the refresh token and accepts 204', () async {
    var logoutCallCount = 0;

    final client = MockClient((request) async {
      logoutCallCount++;

      expect(request.method, 'POST');
      expect(request.url.path, '/auth/logout');

      final body = jsonDecode(request.body) as Map<String, dynamic>;

      expect(body['refreshToken'], 'current-refresh');

      return http.Response('', 204);
    });

    final apiService = ApiService(
      httpClient: client,
      authTokenCoordinator: coordinator,
    );

    await apiService.logout(refreshToken: 'current-refresh');

    expect(logoutCallCount, 1);
  });
}

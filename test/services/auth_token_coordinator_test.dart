import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/auth_tokens.dart';
import 'package:noahs_ark_app/services/api_exception.dart';
import 'package:noahs_ark_app/services/auth_session_storage.dart';
import 'package:noahs_ark_app/services/auth_token_coordinator.dart';

void main() {
  late AuthSessionStorage storage;
  late AuthTokenCoordinator coordinator;

  AuthTokens createTokens({
    required String accessToken,
    required String refreshToken,
    DateTime? expiresAt,
  }) {
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      refreshTokenExpiresAt:
          expiresAt ?? DateTime.now().toUtc().add(const Duration(days: 30)),
    );
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});

    storage = AuthSessionStorage(storage: const FlutterSecureStorage());

    coordinator = AuthTokenCoordinator(storage: storage);
  });

  test('shares one refresh across concurrent unauthorized requests', () async {
    final original = createTokens(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
    );

    final replacement = createTokens(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
    );

    await storage.saveTokens(original);

    final refreshGate = Completer<void>();
    var refreshCallCount = 0;

    Future<AuthTokens> refresh(String refreshToken) async {
      refreshCallCount++;

      expect(refreshToken, 'old-refresh');

      await refreshGate.future;

      return replacement;
    }

    final first = coordinator.refreshAfterUnauthorized(
      rejectedAccessToken: 'old-access',
      refresh: refresh,
    );

    final second = coordinator.refreshAfterUnauthorized(
      rejectedAccessToken: 'old-access',
      refresh: refresh,
    );

    await Future<void>.delayed(Duration.zero);

    expect(refreshCallCount, 1);

    refreshGate.complete();

    final results = await Future.wait([first, second]);

    expect(results[0].accessToken, 'new-access');

    expect(results[1].accessToken, 'new-access');

    expect(refreshCallCount, 1);

    final stored = await storage.readTokens();

    expect(stored?.refreshToken, 'new-refresh');
  });

  test('does not refresh again for a stale unauthorized response', () async {
    final current = createTokens(
      accessToken: 'already-refreshed-access',
      refreshToken: 'already-refreshed-refresh',
    );

    await storage.saveTokens(current);

    var refreshCallCount = 0;

    final result = await coordinator.refreshAfterUnauthorized(
      rejectedAccessToken: 'old-rejected-access',
      refresh: (refreshToken) async {
        refreshCallCount++;
        return current;
      },
    );

    expect(result.accessToken, 'already-refreshed-access');

    expect(refreshCallCount, 0);
  });

  test('deletes stored tokens when refresh is unauthorized', () async {
    await storage.saveTokens(
      createTokens(
        accessToken: 'expired-access',
        refreshToken: 'rejected-refresh',
      ),
    );

    await expectLater(
      coordinator.refreshAfterUnauthorized(
        rejectedAccessToken: 'expired-access',
        refresh: (refreshToken) async {
          throw const ApiException(
            statusCode: 401,
            message: 'Invalid or expired refresh token',
          );
        },
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.isUnauthorized,
          'isUnauthorized',
          isTrue,
        ),
      ),
    );

    expect(await storage.readTokens(), isNull);
  });

  test('rejects a locally expired refresh token', () async {
    await storage.saveTokens(
      createTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.utc(2020, 1, 1),
      ),
    );

    var refreshCallCount = 0;

    await expectLater(
      coordinator.refreshAfterUnauthorized(
        rejectedAccessToken: 'access',
        refresh: (refreshToken) async {
          refreshCallCount++;

          return createTokens(
            accessToken: 'new-access',
            refreshToken: 'new-refresh',
          );
        },
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.isUnauthorized,
          'isUnauthorized',
          isTrue,
        ),
      ),
    );

    expect(refreshCallCount, 0);

    expect(await storage.readTokens(), isNull);
  });
}

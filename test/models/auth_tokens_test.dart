import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/auth_tokens.dart';

void main() {
  test('parses and serializes an authentication token bundle', () {
    final tokens = AuthTokens.fromJson({
      'accessToken': 'test-access-token',
      'refreshToken': 'test-refresh-token',
      'refreshTokenExpiresAt': '2026-10-20T10:00:00.000Z',
    });

    expect(tokens.accessToken, 'test-access-token');
    expect(tokens.refreshToken, 'test-refresh-token');
    expect(tokens.refreshTokenExpiresAt, DateTime.utc(2026, 10, 20, 10));

    expect(tokens.toJson(), {
      'accessToken': 'test-access-token',
      'refreshToken': 'test-refresh-token',
      'refreshTokenExpiresAt': '2026-10-20T10:00:00.000Z',
    });
  });

  test('detects refresh token expiry', () {
    final tokens = AuthTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
      refreshTokenExpiresAt: DateTime.utc(2026, 10, 20, 10),
    );

    expect(
      tokens.isRefreshTokenExpiredAt(DateTime.utc(2026, 10, 20, 9, 59)),
      isFalse,
    );

    expect(
      tokens.isRefreshTokenExpiredAt(DateTime.utc(2026, 10, 20, 10)),
      isTrue,
    );
  });

  test('rejects an incomplete token bundle', () {
    expect(
      () => AuthTokens.fromJson({
        'refreshToken': 'refresh',
        'refreshTokenExpiresAt': '2026-10-20T10:00:00.000Z',
      }),
      throwsFormatException,
    );

    expect(
      () => AuthTokens.fromJson({
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'refreshTokenExpiresAt': 'invalid-date',
      }),
      throwsFormatException,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/auth_session.dart';

void main() {
  test('parses an unverified authenticated session', () {
    final session = AuthSession.fromJson({
      'accessToken': 'test-access-token',
      'refreshToken': 'test-refresh-token',
      'refreshTokenExpiresAt': '2026-10-20T10:00:00.000Z',
      'user': {
        'id': '31',
        'displayName': 'Day 31 User',
        'email': 'day31@example.com',
        'emailVerifiedAt': null,
        'createdAt': '2026-08-20T04:30:00.000Z',
      },
    });

    expect(session.accessToken, 'test-access-token');

    expect(session.refreshToken, 'test-refresh-token');

    expect(session.refreshTokenExpiresAt, DateTime.utc(2026, 10, 20, 10));

    expect(session.user.id, 31);
    expect(session.user.displayName, 'Day 31 User');
    expect(session.user.email, 'day31@example.com');
    expect(session.user.emailVerifiedAt, isNull);
    expect(session.user.isEmailVerified, isFalse);
  });

  test('parses a verified authenticated session', () {
    final session = AuthSession.fromJson({
      'accessToken': 'test-access-token',
      'refreshToken': 'test-refresh-token',
      'refreshTokenExpiresAt': '2026-10-20T10:00:00.000Z',
      'user': {
        'id': 31,
        'displayName': 'Day 31 User',
        'email': 'day31@example.com',
        'emailVerifiedAt': '2026-09-19T03:15:00.000Z',
        'createdAt': '2026-08-20T04:30:00.000Z',
      },
    });

    expect(session.user.emailVerifiedAt, DateTime.utc(2026, 9, 19, 3, 15));

    expect(session.user.isEmailVerified, isTrue);
  });

  test('rejects a session without complete tokens', () {
    expect(
      () => AuthSession.fromJson({
        'refreshToken': 'refresh-token',
        'refreshTokenExpiresAt': '2026-10-20T10:00:00.000Z',
        'user': {
          'id': 31,
          'displayName': 'User',
          'email': 'user@example.com',
          'emailVerifiedAt': null,
          'createdAt': '2026-08-20T04:30:00.000Z',
        },
      }),
      throwsFormatException,
    );

    expect(
      () => AuthSession.fromJson({
        'accessToken': 'access-token',
        'refreshTokenExpiresAt': '2026-10-20T10:00:00.000Z',
        'user': {
          'id': 31,
          'displayName': 'User',
          'email': 'user@example.com',
          'emailVerifiedAt': null,
          'createdAt': '2026-08-20T04:30:00.000Z',
        },
      }),
      throwsFormatException,
    );
  });
}

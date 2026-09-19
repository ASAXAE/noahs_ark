import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/auth_session.dart';

void main() {
  test('parses an unverified authenticated session', () {
    final session = AuthSession.fromJson({
      'accessToken': 'test-access-token',
      'user': {
        'id': '31',
        'displayName': 'Day 31 User',
        'email': 'day31@example.com',
        'emailVerifiedAt': null,
        'createdAt': '2026-08-20T04:30:00.000Z',
      },
    });

    expect(session.accessToken, 'test-access-token');
    expect(session.user.id, 31);
    expect(session.user.displayName, 'Day 31 User');
    expect(session.user.email, 'day31@example.com');
    expect(session.user.emailVerifiedAt, isNull);
    expect(session.user.isEmailVerified, isFalse);
    expect(session.user.createdAt, DateTime.utc(2026, 8, 20, 4, 30));
  });

  test('parses a verified authenticated session', () {
    final session = AuthSession.fromJson({
      'accessToken': 'test-access-token',
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

  test('rejects a response without an access token', () {
    expect(
      () => AuthSession.fromJson({
        'user': {
          'id': '31',
          'displayName': 'Day 31 User',
          'email': 'day31@example.com',
          'emailVerifiedAt': null,
          'createdAt': '2026-08-20T04:30:00.000Z',
        },
      }),
      throwsFormatException,
    );
  });
}

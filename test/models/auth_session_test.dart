import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/auth_session.dart';

void main() {
  test('parses an authenticated session response', () {
    final session = AuthSession.fromJson({
      'accessToken': 'test-access-token',
      'user': {
        'id': '31',
        'displayName': 'Day 31 User',
        'email': 'day31@example.com',
        'createdAt': '2026-08-20T04:30:00.000Z',
      },
    });

    expect(session.accessToken, 'test-access-token');
    expect(session.user.id, 31);
    expect(session.user.displayName, 'Day 31 User');
    expect(session.user.email, 'day31@example.com');
    expect(session.user.createdAt, DateTime.utc(2026, 8, 20, 4, 30));
  });

  test('rejects a response without an access token', () {
    expect(
      () => AuthSession.fromJson({
        'user': {
          'id': '31',
          'displayName': 'Day 31 User',
          'email': 'day31@example.com',
          'createdAt': '2026-08-20T04:30:00.000Z',
        },
      }),
      throwsFormatException,
    );
  });
}

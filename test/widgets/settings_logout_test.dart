import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/auth_session.dart';
import 'package:noahs_ark_app/models/auth_tokens.dart';
import 'package:noahs_ark_app/models/auth_user.dart';
import 'package:noahs_ark_app/screens/settings/settings_page.dart';
import 'package:noahs_ark_app/services/api_service.dart';
import 'package:noahs_ark_app/services/auth_session_storage.dart';

class FakeApiService extends ApiService {
  FakeApiService({this.logoutError});

  final Object? logoutError;

  int logoutCallCount = 0;
  String? receivedRefreshToken;

  @override
  Future<void> logout({required String refreshToken}) async {
    logoutCallCount++;
    receivedRefreshToken = refreshToken;

    final error = logoutError;

    if (error != null) {
      throw error;
    }
  }
}

class FakeAuthSessionStorage extends AuthSessionStorage {
  int deleteCallCount = 0;

  @override
  Future<void> deleteTokens() async {
    deleteCallCount++;
  }
}

void main() {
  AuthSession createSession() {
    return AuthSession(
      tokens: AuthTokens(
        accessToken: 'current-access',
        refreshToken: 'current-refresh',
        refreshTokenExpiresAt: DateTime.utc(2030, 1, 1),
      ),
      user: AuthUser(
        id: 1,
        displayName: 'Noah',
        email: 'noah@example.com',
        emailVerifiedAt: null,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
  }

  Future<void> pumpSettings(
    WidgetTester tester, {
    required ValueNotifier<AuthSession?> notifier,
    required ApiService apiService,
    required AuthSessionStorage storage,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          authSessionNotifier: notifier,
          onThoughtsChanged: () async {},
          apiService: apiService,
          authSessionStorage: storage,
        ),
      ),
    );
  }

  testWidgets('logout revokes the remote session and clears local tokens', (
    tester,
  ) async {
    final notifier = ValueNotifier<AuthSession?>(createSession());
    addTearDown(notifier.dispose);

    final apiService = FakeApiService();
    final storage = FakeAuthSessionStorage();

    await pumpSettings(
      tester,
      notifier: notifier,
      apiService: apiService,
      storage: storage,
    );

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    await tester.pumpAndSettle();

    expect(apiService.logoutCallCount, 1);
    expect(apiService.receivedRefreshToken, 'current-refresh');
    expect(storage.deleteCallCount, 1);
    expect(notifier.value, isNull);
    expect(find.text('已退出登录，本地记录仍然保留'), findsOneWidget);
  });

  testWidgets('remote failure still clears local tokens', (tester) async {
    final notifier = ValueNotifier<AuthSession?>(createSession());
    addTearDown(notifier.dispose);

    final apiService = FakeApiService(
      logoutError: StateError('server unavailable'),
    );
    final storage = FakeAuthSessionStorage();

    await pumpSettings(
      tester,
      notifier: notifier,
      apiService: apiService,
      storage: storage,
    );

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    await tester.pumpAndSettle();

    expect(apiService.logoutCallCount, 1);
    expect(storage.deleteCallCount, 1);
    expect(notifier.value, isNull);
    expect(find.text('已退出本机，但服务器会话未能撤销'), findsOneWidget);
  });

  testWidgets('cancelling logout changes nothing', (tester) async {
    final session = createSession();
    final notifier = ValueNotifier<AuthSession?>(session);
    addTearDown(notifier.dispose);

    final apiService = FakeApiService();
    final storage = FakeAuthSessionStorage();

    await pumpSettings(
      tester,
      notifier: notifier,
      apiService: apiService,
      storage: storage,
    );

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(apiService.logoutCallCount, 0);
    expect(storage.deleteCallCount, 0);
    expect(notifier.value, same(session));
  });
}

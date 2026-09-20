import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/auth_session.dart';
import 'package:noahs_ark_app/models/auth_user.dart';
import 'package:noahs_ark_app/screens/settings/email_verification_page.dart';
import 'package:noahs_ark_app/screens/settings/settings_page.dart';
import 'package:noahs_ark_app/services/api_service.dart';
import 'package:noahs_ark_app/models/auth_tokens.dart';

class FakeApiService extends ApiService {
  FakeApiService({required this.refreshedUser});

  final AuthUser refreshedUser;

  int resendCallCount = 0;
  int confirmCallCount = 0;
  int fetchCurrentUserCallCount = 0;
  String? submittedToken;

  @override
  Future<void> resendVerificationEmail() async {
    resendCallCount++;
  }

  @override
  Future<void> confirmEmailVerification({required String token}) async {
    confirmCallCount++;
    submittedToken = token;
  }

  @override
  Future<AuthUser> fetchCurrentUser({required String accessToken}) async {
    fetchCurrentUserCallCount++;
    return refreshedUser;
  }
}

AuthUser createUser({required bool isVerified}) {
  return AuthUser(
    id: 64,
    displayName: 'Day 64 User',
    email: 'day64@example.com',
    emailVerifiedAt: isVerified ? DateTime.utc(2026, 9, 19, 5, 30) : null,
    createdAt: DateTime.utc(2026, 9, 19),
  );
}

AuthSession createSession({required bool isVerified}) {
  return AuthSession(
    tokens: AuthTokens(
      accessToken: 'day-64-access-token',
      refreshToken: 'day-65-refresh-token',
      refreshTokenExpiresAt: DateTime.utc(2026, 10, 20),
    ),
    user: createUser(isVerified: isVerified),
  );
}

void main() {
  testWidgets('settings shows unverified status and opens verification page', (
    tester,
  ) async {
    final notifier = ValueNotifier<AuthSession?>(
      createSession(isVerified: false),
    );
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          authSessionNotifier: notifier,
          onThoughtsChanged: () async {},
        ),
      ),
    );

    expect(find.text('邮箱未验证'), findsOneWidget);
    expect(find.text('可以继续验证，本地功能不受影响'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('email-verification-entry')));
    await tester.pumpAndSettle();

    expect(find.text('邮箱验证'), findsOneWidget);
    expect(find.text('邮箱验证只影响账户状态，不会限制本地记录、闪念、录音或备份。'), findsOneWidget);
  });

  testWidgets('resends, validates token and refreshes verified state', (
    tester,
  ) async {
    final initialSession = createSession(isVerified: false);
    final notifier = ValueNotifier<AuthSession?>(initialSession);
    addTearDown(notifier.dispose);

    final fakeApiService = FakeApiService(
      refreshedUser: createUser(isVerified: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EmailVerificationPage(
          session: initialSession,
          authSessionNotifier: notifier,
          apiService: fakeApiService,
        ),
      ),
    );

    expect(find.text('邮箱尚未验证'), findsOneWidget);
    expect(find.text('重新发送验证邮件'), findsOneWidget);

    await tester.tap(find.text('重新发送验证邮件'));
    await tester.pumpAndSettle();

    expect(fakeApiService.resendCallCount, 1);
    expect(find.text('验证请求已提交。如果后端使用本地假发送器，不会收到真实邮件。'), findsOneWidget);

    final confirmButton = find.text('确认邮箱验证');
    await tester.ensureVisible(confirmButton);

    await tester.enterText(find.byType(TextFormField), 'invalid-token');
    await tester.tap(confirmButton);
    await tester.pump();

    expect(find.text('验证令牌应为 64 位小写十六进制字符'), findsOneWidget);
    expect(fakeApiService.confirmCallCount, 0);

    final validToken = 'a' * 64;

    await tester.enterText(find.byType(TextFormField), validToken);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(fakeApiService.confirmCallCount, 1);
    expect(fakeApiService.submittedToken, validToken);
    expect(fakeApiService.fetchCurrentUserCallCount, 1);

    expect(notifier.value?.user.isEmailVerified, isTrue);
    expect(find.text('邮箱已验证'), findsOneWidget);
    expect(find.text('重新发送验证邮件'), findsNothing);
  });
}

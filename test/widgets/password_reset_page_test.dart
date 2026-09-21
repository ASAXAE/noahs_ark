import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/screens/auth/password_reset_page.dart';
import 'package:noahs_ark_app/services/api_service.dart';

class FakeApiService extends ApiService {
  String? requestedEmail;
  String? confirmedToken;
  String? confirmedPassword;

  @override
  Future<void> requestPasswordReset({required String email}) async {
    requestedEmail = email;
  }

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String password,
  }) async {
    confirmedToken = token;
    confirmedPassword = password;
  }
}

void main() {
  testWidgets('validates an empty password reset email', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: PasswordResetPage(apiService: FakeApiService())),
    );

    await tester.tap(find.byKey(const Key('password-reset-request-button')));
    await tester.pump();

    expect(find.text('请输入邮箱'), findsOneWidget);
  });

  testWidgets('requests and confirms a password reset', (tester) async {
    final apiService = FakeApiService();
    bool? resetCompleted;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    resetCompleted = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) =>
                            PasswordResetPage(apiService: apiService),
                      ),
                    );
                  },
                  child: const Text('打开重置页'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开重置页'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('password-reset-email')),
      'test@example.com',
    );

    await tester.tap(find.byKey(const Key('password-reset-request-button')));
    await tester.pumpAndSettle();

    expect(apiService.requestedEmail, 'test@example.com');
    expect(find.byKey(const Key('password-reset-token')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('password-reset-token')),
      'a' * 64,
    );
    await tester.enterText(
      find.byKey(const Key('password-reset-password')),
      'Replacement123',
    );
    await tester.enterText(
      find.byKey(const Key('password-reset-confirm-password')),
      'Replacement123',
    );

    final confirmButton = find.byKey(
      const Key('password-reset-confirm-button'),
    );

    await tester.ensureVisible(confirmButton);
    await tester.pumpAndSettle();
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(apiService.confirmedToken, 'a' * 64);
    expect(apiService.confirmedPassword, 'Replacement123');
    expect(resetCompleted, isTrue);
  });
}

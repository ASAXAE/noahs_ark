import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/screens/auth/login_page.dart';
import 'package:noahs_ark_app/screens/auth/password_reset_page.dart';

void main() {
  testWidgets('opens password reset with email and handles successful return', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    await tester.enterText(
      find.byKey(const Key('login-email')),
      'test@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'OldPassword123',
    );

    await tester.tap(find.byKey(const Key('open-password-reset')));
    await tester.pumpAndSettle();

    expect(find.byType(PasswordResetPage), findsOneWidget);

    final resetEmailField = tester.widget<TextFormField>(
      find.byKey(const Key('password-reset-email')),
    );

    expect(resetEmailField.controller?.text, 'test@example.com');

    final resetPageContext = tester.element(find.byType(PasswordResetPage));

    Navigator.of(resetPageContext).pop(true);
    await tester.pumpAndSettle();

    expect(find.text('密码已重置，请使用新密码登录'), findsOneWidget);

    final loginPasswordField = tester.widget<TextFormField>(
      find.byKey(const Key('login-password')),
    );

    expect(loginPasswordField.controller?.text, isEmpty);
    final passwordEditableText = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('login-password')),
        matching: find.byType(EditableText),
      ),
    );

    expect(passwordEditableText.focusNode.hasFocus, isTrue);
  });
}

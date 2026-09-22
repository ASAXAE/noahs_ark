import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/screens/settings/account_deletion_page.dart';
import 'package:noahs_ark_app/services/api_exception.dart';
import 'package:noahs_ark_app/services/api_service.dart';

class FakeApiService extends ApiService {
  FakeApiService({this.deletionError});

  final Object? deletionError;

  int deletionCallCount = 0;
  String? submittedPassword;

  @override
  Future<void> deleteAccount({required String password}) async {
    deletionCallCount++;
    submittedPassword = password;

    final error = deletionError;

    if (error != null) {
      throw error;
    }
  }
}

void main() {
  testWidgets('explains cloud deletion and local retention', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AccountDeletionPage(apiService: FakeApiService())),
    );

    expect(find.text('此操作不可恢复'), findsOneWidget);

    expect(find.text('当前设备上的内容会保留'), findsOneWidget);

    expect(find.textContaining('本机 SQLite'), findsOneWidget);
  });

  testWidgets('validates an empty current password', (tester) async {
    final apiService = FakeApiService();

    await tester.pumpWidget(
      MaterialApp(home: AccountDeletionPage(apiService: apiService)),
    );

    final button = find.byKey(const Key('account-deletion-button'));

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(find.text('请输入当前密码'), findsOneWidget);

    expect(apiService.deletionCallCount, 0);
  });

  testWidgets('submits the exact password and returns success', (tester) async {
    final apiService = FakeApiService();
    bool? deletionCompleted;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    deletionCompleted = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) =>
                            AccountDeletionPage(apiService: apiService),
                      ),
                    );
                  },
                  child: const Text('打开删除页'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开删除页'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('account-deletion-password')),
      ' Current Password 123 ',
    );

    final button = find.byKey(const Key('account-deletion-button'));

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(apiService.submittedPassword, ' Current Password 123 ');

    expect(deletionCompleted, isTrue);
  });

  testWidgets('keeps the page open when the password is wrong', (tester) async {
    final apiService = FakeApiService(
      deletionError: const ApiException(
        statusCode: 403,
        message: 'Current password is incorrect',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: AccountDeletionPage(apiService: apiService)),
    );

    await tester.enterText(
      find.byKey(const Key('account-deletion-password')),
      'WrongPassword456',
    );

    final button = find.byKey(const Key('account-deletion-button'));

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('当前密码不正确，云端账号未删除'), findsOneWidget);

    expect(find.text('删除云端账号'), findsOneWidget);
  });
}

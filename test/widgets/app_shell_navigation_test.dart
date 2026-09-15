import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/screens/shell/app_shell.dart';

class _CapturePageProbe extends StatefulWidget {
  const _CapturePageProbe({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_CapturePageProbe> createState() => _CapturePageProbeState();
}

class _CapturePageProbeState extends State<_CapturePageProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('capture page'));
  }
}

void main() {
  testWidgets('keeps the capture destination mounted while switching tabs', (
    tester,
  ) async {
    var captureInitCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          arkPage: const Center(child: Text('ark page')),
          capturePage: _CapturePageProbe(
            onInit: () {
              captureInitCount++;
            },
          ),
          profilePage: const Center(child: Text('profile page')),
        ),
      ),
    );

    await tester.tap(find.text('闪念'));
    await tester.pumpAndSettle();
    expect(find.text('capture page'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('方舟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('闪念'));
    await tester.pumpAndSettle();

    expect(find.text('capture page'), findsOneWidget);
    expect(captureInitCount, 1);
  });
}

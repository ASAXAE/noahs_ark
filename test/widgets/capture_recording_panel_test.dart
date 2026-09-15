import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/capture_recording_state.dart';
import 'package:noahs_ark_app/screens/capture/capture_recording_panel.dart';

Future<void> _pumpPanel(
  WidgetTester tester, {
  required CaptureRecordingState state,
  required VoidCallback onPressed,
  Duration elapsed = Duration.zero,
  double recordingAudioLevel = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            CaptureRecordingPanel(
              state: state,
              recordingAudioLevel: recordingAudioLevel,
              elapsed: elapsed,
              onPressed: onPressed,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('idle shows a working start button', (tester) async {
    var presses = 0;

    await _pumpPanel(
      tester,
      state: const CaptureRecordingState.idle(),
      onPressed: () {
        presses++;
      },
    );

    expect(find.text('开始录音'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    final button = tester.widget<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text('开始录音'));
    expect(presses, 1);
  });

  testWidgets('recording shows stop, elapsed time, and level', (tester) async {
    await _pumpPanel(
      tester,
      state: CaptureRecordingState.recording(
        audioPath: '/capture/test.wav',
        startedAt: DateTime(2026, 1, 1),
      ),
      elapsed: const Duration(seconds: 62),
      recordingAudioLevel: 0.5,
      onPressed: () {},
    );

    expect(find.text('停止并保存'), findsOneWidget);
    expect(find.text('已录制 01:02'), findsOneWidget);
    expect(find.text('实时音量'), findsOneWidget);

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.5);
  });

  testWidgets('stopping disables the button', (tester) async {
    await _pumpPanel(
      tester,
      state: CaptureRecordingState.stopping(
        audioPath: '/capture/test.wav',
        startedAt: DateTime(2026, 1, 1),
      ),
      elapsed: const Duration(seconds: 62),
      onPressed: () {},
    );

    expect(find.text('处理中…'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(button.onPressed, isNull);
  });
}

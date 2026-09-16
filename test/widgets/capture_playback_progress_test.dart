import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/screens/capture/capture_playback_progress.dart';

Future<void> _pumpProgress(
  WidgetTester tester, {
  required Duration position,
  required Duration duration,
  required bool isLoading,
  required Future<void> Function(Duration position) onSeek,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CapturePlaybackProgress(
          position: position,
          duration: duration,
          isLoading: isLoading,
          onSeek: onSeek,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows current position and total duration', (tester) async {
    await _pumpProgress(
      tester,
      position: const Duration(seconds: 65),
      duration: const Duration(seconds: 125),
      isLoading: false,
      onSeek: (_) async {},
    );

    expect(find.text('01:05'), findsOneWidget);
    expect(find.text('02:05'), findsOneWidget);

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, closeTo(65 / 125, 0.001));
    expect(slider.onChanged, isNotNull);
  });

  testWidgets('disables seeking while audio is loading', (tester) async {
    await _pumpProgress(
      tester,
      position: Duration.zero,
      duration: const Duration(minutes: 2),
      isLoading: true,
      onSeek: (_) async {},
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
    expect(slider.onChangeEnd, isNull);
  });

  testWidgets('shows dragged time and seeks when dragging ends', (
    tester,
  ) async {
    Duration? soughtPosition;

    await _pumpProgress(
      tester,
      position: const Duration(seconds: 10),
      duration: const Duration(minutes: 2),
      isLoading: false,
      onSeek: (position) async {
        soughtPosition = position;
      },
    );

    var slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(0.5);
    await tester.pump();

    expect(find.text('01:00'), findsOneWidget);
    expect(find.text('02:00'), findsOneWidget);

    slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeEnd!(0.5);
    await tester.pump();

    expect(soughtPosition, const Duration(minutes: 1));
  });
}

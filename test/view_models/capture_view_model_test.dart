import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/capture_recording_state.dart';
import 'package:noahs_ark_app/repositories/capture_repository.dart';
import 'package:noahs_ark_app/services/audio_recorder_service.dart';
import 'package:noahs_ark_app/view_models/capture_view_model.dart';

void main() {
  group('CaptureViewModel queue', () {
    test('runs drafts serially in FIFO order', () async {
      final firstCanFinish = Completer<void>();
      final startedDraftIds = <int>[];

      final viewModel = _createViewModel(
        runTranscription: (draftId) async {
          startedDraftIds.add(draftId);

          if (draftId == 11) {
            await firstCanFinish.future;
          }
        },
      );

      expect(viewModel.submitDraft(11), isTrue);
      expect(viewModel.activeDraftId, 11);

      expect(viewModel.submitDraft(22), isTrue);
      expect(viewModel.submitDraft(11), isFalse);
      expect(viewModel.submitDraft(0), isFalse);

      expect(viewModel.activeDraftId, 11);
      expect(viewModel.queuedDraftIds, [22]);
      expect(viewModel.queuePositionFor(22), 1);
      expect(() => viewModel.queuedDraftIds.add(33), throwsUnsupportedError);

      firstCanFinish.complete();
      await viewModel.waitUntilIdle();

      expect(startedDraftIds, [11, 22]);
      expect(viewModel.activeDraftId, isNull);
      expect(viewModel.queuedDraftIds, isEmpty);
    });

    test('cancels a queued draft before it starts', () async {
      final firstCanFinish = Completer<void>();
      final startedDraftIds = <int>[];

      final viewModel = _createViewModel(
        runTranscription: (draftId) async {
          startedDraftIds.add(draftId);

          if (draftId == 11) {
            await firstCanFinish.future;
          }
        },
      );

      viewModel.submitDraft(11);
      viewModel.submitDraft(22);

      expect(viewModel.cancelQueuedDraft(22), isTrue);
      expect(viewModel.cancelQueuedDraft(22), isFalse);
      expect(viewModel.queuedDraftIds, isEmpty);

      firstCanFinish.complete();
      await viewModel.waitUntilIdle();

      expect(startedDraftIds, [11]);
    });

    test('continues with the next draft after a failure', () async {
      final startedDraftIds = <int>[];

      final viewModel = _createViewModel(
        runTranscription: (draftId) async {
          startedDraftIds.add(draftId);

          if (draftId == 11) {
            throw StateError('simulated failure');
          }
        },
      );

      viewModel.submitDraft(11);
      viewModel.submitDraft(22);

      await viewModel.waitUntilIdle();

      expect(startedDraftIds, [11, 22]);
      expect(viewModel.activeDraftId, isNull);
      expect(viewModel.queuedDraftIds, isEmpty);
    });
    test('notifies listeners for every visible queue change', () async {
      final firstCanFinish = Completer<void>();
      final snapshots = <String>[];

      final viewModel = _createViewModel(
        runTranscription: (draftId) async {
          if (draftId == 11) {
            await firstCanFinish.future;
          }
        },
      );

      viewModel.addListener(() {
        snapshots.add(
          '${viewModel.activeDraftId}:'
          '${viewModel.queuedDraftIds.join(',')}',
        );
      });

      viewModel.submitDraft(11);
      viewModel.submitDraft(22);
      viewModel.cancelQueuedDraft(22);

      firstCanFinish.complete();
      await viewModel.waitUntilIdle();

      expect(snapshots, ['null:11', '11:', '11:22', '11:', 'null:']);
    });

    test('notifies once after the whole queue drains', () async {
      final firstCanFinish = Completer<void>();
      final startedDraftIds = <int>[];
      var queueDrainedCount = 0;

      final viewModel = _createViewModel(
        runTranscription: (draftId) async {
          startedDraftIds.add(draftId);

          if (draftId == 11) {
            await firstCanFinish.future;
          }
        },
        onQueueDrained: () {
          queueDrainedCount++;
        },
      );

      viewModel.submitDraft(11);
      viewModel.submitDraft(22);

      expect(queueDrainedCount, 0);

      firstCanFinish.complete();
      await viewModel.waitUntilIdle();

      expect(startedDraftIds, [11, 22]);
      expect(queueDrainedCount, 1);
    });
  });

  group('CaptureViewModel recording', () {
    test('forwards recording commands and publishes state changes', () async {
      final recorder = _FakeCaptureAudioRecorder();
      final viewModel = _createViewModel(
        recorder: recorder,
        runTranscription: (_) async {},
      );
      final phases = <CaptureRecordingPhase>[];

      viewModel.addListener(() {
        phases.add(viewModel.recordingState.phase);
      });

      expect(viewModel.recordingState.phase, CaptureRecordingPhase.idle);

      expect(await viewModel.startRecording(), isTrue);
      expect(await viewModel.startRecording(), isFalse);
      expect(await viewModel.stopAndSaveRecording(), 42);

      expect(recorder.startCalls, 1);
      expect(recorder.stopCalls, 1);
      expect(phases, [
        CaptureRecordingPhase.requestingPermission,
        CaptureRecordingPhase.starting,
        CaptureRecordingPhase.recording,
        CaptureRecordingPhase.stopping,
        CaptureRecordingPhase.idle,
      ]);
    });

    test('normalizes live audio level and resets when stopping', () async {
      final recorder = _FakeCaptureAudioRecorder();
      final viewModel = _createViewModel(
        recorder: recorder,
        runTranscription: (_) async {},
      );

      expect(viewModel.recordingAudioLevel, 0);

      recorder.emitAudioLevelDbfs(-30); // 未录音：忽略
      expect(viewModel.recordingAudioLevel, 0);

      expect(await viewModel.startRecording(), isTrue);

      recorder.emitAudioLevelDbfs(-60);
      expect(viewModel.recordingAudioLevel, 0);

      recorder.emitAudioLevelDbfs(-30);
      expect(viewModel.recordingAudioLevel, 0.5);

      recorder.emitAudioLevelDbfs(0);
      expect(viewModel.recordingAudioLevel, 1);

      recorder.emitAudioLevelDbfs(double.nan); // 无效值：忽略
      expect(viewModel.recordingAudioLevel, 1);

      final stopFuture = viewModel.stopAndSaveRecording();
      expect(viewModel.recordingAudioLevel, 0); // 进入 stopping 即归零

      recorder.emitAudioLevelDbfs(-12); // 晚到事件：忽略
      expect(viewModel.recordingAudioLevel, 0);

      expect(await stopFuture, 42);
    });
  });
}

CaptureViewModel _createViewModel({
  required CaptureTranscriptionRunner runTranscription,
  void Function()? onQueueDrained,
  _FakeCaptureAudioRecorder? recorder,
}) {
  final repository = CaptureRepository(
    audioRecorderService: recorder ?? _FakeCaptureAudioRecorder(),
    insertCaptureDraft: (_) async => 42,
  );

  final viewModel = CaptureViewModel(
    repository: repository,
    runTranscription: runTranscription,
    onQueueDrained: onQueueDrained,
  );

  addTearDown(() async {
    viewModel.dispose();
    await repository.dispose();
  });

  return viewModel;
}

class _FakeCaptureAudioRecorder implements CaptureAudioRecorder {
  int startCalls = 0;
  int stopCalls = 0;

  final StreamController<double> _audioLevelDbfsController =
      StreamController<double>.broadcast(sync: true);

  @override
  Stream<double> get audioLevelDbfs => _audioLevelDbfsController.stream;

  void emitAudioLevelDbfs(double value) {
    _audioLevelDbfsController.add(value);
  }

  final StreamController<String> _externallyStoppedController =
      StreamController<String>.broadcast(sync: true);

  @override
  Stream<String> get externallyStoppedRecordingPaths =>
      _externallyStoppedController.stream;

  @override
  Future<bool> requestPermission() async {
    return true;
  }

  @override
  Future<String> startRecordingAfterPermissionGranted() async {
    startCalls++;
    return '/capture/test.wav';
  }

  @override
  Future<String?> stopRecording() async {
    stopCalls++;
    return '/capture/test.wav';
  }

  @override
  Future<CaptureRecordingRecovery?> recoverPendingRecording() async {
    return null;
  }

  @override
  Future<void> clearPendingRecording() async {}

  @override
  Future<void> dispose() async {
    await _audioLevelDbfsController.close();
    await _externallyStoppedController.close();
  }
}

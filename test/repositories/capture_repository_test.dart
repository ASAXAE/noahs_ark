import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/capture_recording_state.dart';
import 'package:noahs_ark_app/repositories/capture_repository.dart';
import 'package:noahs_ark_app/services/audio_recorder_service.dart';
import 'package:noahs_ark_app/models/capture_draft.dart';

void main() {
  group('CaptureRepository recording state', () {
    test('does not start when microphone permission is denied', () async {
      final recorder = _FakeCaptureAudioRecorder(permissionGranted: false);
      final repository = CaptureRepository(audioRecorderService: recorder);
      addTearDown(repository.dispose);

      final started = await repository.startRecording();

      expect(started, isFalse);
      expect(recorder.startCalls, 0);
      expect(
        repository.currentRecordingState.failure,
        CaptureRecordingFailure.permissionDenied,
      );
    });

    test('owns the recording state and prevents duplicate starts', () async {
      final recorder = _FakeCaptureAudioRecorder();
      final repository = CaptureRepository(audioRecorderService: recorder);
      addTearDown(repository.dispose);

      final phases = <CaptureRecordingPhase>[];

      repository.recordingState.addListener(() {
        phases.add(repository.currentRecordingState.phase);
      });

      expect(await repository.startRecording(), isTrue);
      expect(await repository.startRecording(), isFalse);

      expect(recorder.startCalls, 1);
      expect(phases, [
        CaptureRecordingPhase.requestingPermission,
        CaptureRecordingPhase.starting,
        CaptureRecordingPhase.recording,
      ]);
      expect(repository.currentRecordingState.isRecording, isTrue);
      expect(repository.currentRecordingState.audioPath, '/capture/test.wav');
    });

    test('publishes startFailed when the recorder throws', () async {
      final recorder = _FakeCaptureAudioRecorder(
        startError: StateError('simulated start failure'),
      );
      final repository = CaptureRepository(audioRecorderService: recorder);
      addTearDown(repository.dispose);

      await expectLater(
        repository.startRecording(),
        throwsA(isA<StateError>()),
      );

      expect(
        repository.currentRecordingState.failure,
        CaptureRecordingFailure.startFailed,
      );
    });

    test('stops once, saves one draft and returns to idle', () async {
      final recorder = _FakeCaptureAudioRecorder();
      CaptureDraft? savedDraft;

      final repository = CaptureRepository(
        audioRecorderService: recorder,
        insertCaptureDraft: (draft) async {
          savedDraft = draft;
          return 42;
        },
      );
      addTearDown(repository.dispose);

      expect(await repository.startRecording(), isTrue);
      expect(await repository.stopAndSaveRecording(), 42);

      expect(recorder.stopCalls, 1);
      expect(savedDraft?.audioPath, '/capture/test.wav');
      expect(
        repository.currentRecordingState.phase,
        CaptureRecordingPhase.idle,
      );
    });

    test('saves an externally stopped recording exactly once', () async {
      final recorder = _FakeCaptureAudioRecorder();
      CaptureDraft? savedDraft;
      var insertCalls = 0;

      final repository = CaptureRepository(
        audioRecorderService: recorder,
        insertCaptureDraft: (draft) async {
          insertCalls++;
          savedDraft = draft;
          return 42;
        },
      );
      addTearDown(repository.dispose);

      expect(await repository.startRecording(), isTrue);

      recorder.stopExternally();
      recorder.stopExternally();

      await Future<void>.delayed(Duration.zero);

      expect(recorder.stopCalls, 0);
      expect(insertCalls, 1);
      expect(savedDraft?.audioPath, '/capture/test.wav');
      expect(
        repository.currentRecordingState.phase,
        CaptureRecordingPhase.idle,
      );
    });

    test('does not save when stopping returns no audio path', () async {
      final recorder = _FakeCaptureAudioRecorder(stopPath: null);
      var insertCalls = 0;

      final repository = CaptureRepository(
        audioRecorderService: recorder,
        insertCaptureDraft: (draft) async {
          insertCalls++;
          return 42;
        },
      );
      addTearDown(repository.dispose);

      await repository.startRecording();

      expect(await repository.stopAndSaveRecording(), isNull);
      expect(insertCalls, 0);
      expect(
        repository.currentRecordingState.failure,
        CaptureRecordingFailure.stopFailed,
      );
    });

    test('retains the audio path when saving the draft fails', () async {
      final recorder = _FakeCaptureAudioRecorder();

      final repository = CaptureRepository(
        audioRecorderService: recorder,
        insertCaptureDraft: (draft) async {
          throw StateError('simulated save failure');
        },
      );
      addTearDown(repository.dispose);

      await repository.startRecording();

      await expectLater(
        repository.stopAndSaveRecording(),
        throwsA(isA<StateError>()),
      );

      expect(
        repository.currentRecordingState.failure,
        CaptureRecordingFailure.saveFailed,
      );
      expect(repository.currentRecordingState.audioPath, '/capture/test.wav');
    });

    test('publishes interruption and saves only one draft', () async {
      final recorder = _FakeCaptureAudioRecorder();
      var insertCalls = 0;

      final repository = CaptureRepository(
        audioRecorderService: recorder,
        insertCaptureDraft: (draft) async {
          insertCalls++;
          return 42;
        },
      );
      addTearDown(repository.dispose);

      await repository.startRecording();

      final phases = <CaptureRecordingPhase>[];
      repository.recordingState.addListener(() {
        phases.add(repository.currentRecordingState.phase);
      });

      expect(await repository.stopRecordingForInterruption(), 42);
      expect(await repository.stopRecordingForInterruption(), isNull);

      expect(phases, [
        CaptureRecordingPhase.interrupted,
        CaptureRecordingPhase.stopping,
        CaptureRecordingPhase.idle,
      ]);
      expect(recorder.stopCalls, 1);
      expect(insertCalls, 1);
    });

    test('reconnects an active foreground recording', () async {
      final startedAt = DateTime(2026, 9, 14, 9, 30);
      final recorder = _FakeCaptureAudioRecorder(
        pendingRecovery: CaptureRecordingRecovery(
          kind: CaptureRecordingRecoveryKind.active,
          audioPath: '/capture/active.wav',
          startedAt: startedAt,
        ),
      );
      final repository = CaptureRepository(audioRecorderService: recorder);
      addTearDown(repository.dispose);

      final outcome = await repository.recoverPendingRecording();

      expect(outcome, CaptureRecordingRecoveryOutcome.active);
      expect(repository.currentRecordingState.isRecording, isTrue);
      expect(repository.currentRecordingState.audioPath, '/capture/active.wav');
      expect(repository.currentRecordingState.startedAt, startedAt);
      expect(recorder.clearPendingCalls, 0);
    });

    test('saves a recovered recording once and clears its marker', () async {
      final startedAt = DateTime(2026, 9, 14, 9, 30);
      final recorder = _FakeCaptureAudioRecorder(
        pendingRecovery: CaptureRecordingRecovery(
          kind: CaptureRecordingRecoveryKind.recovered,
          audioPath: '/capture/interrupted_recovered.wav',
          startedAt: startedAt,
        ),
      );
      CaptureDraft? savedDraft;
      var insertCalls = 0;
      final repository = CaptureRepository(
        audioRecorderService: recorder,
        getCaptureDraftByAudioPath: (_) async => null,
        insertCaptureDraft: (draft) async {
          insertCalls++;
          savedDraft = draft;
          return 42;
        },
      );
      addTearDown(repository.dispose);

      final outcome = await repository.recoverPendingRecording();

      expect(outcome, CaptureRecordingRecoveryOutcome.recovered);
      expect(insertCalls, 1);
      expect(savedDraft?.audioPath, '/capture/interrupted_recovered.wav');
      expect(savedDraft?.createdAt, startedAt);
      expect(recorder.clearPendingCalls, 1);
      expect(
        repository.currentRecordingState.phase,
        CaptureRecordingPhase.idle,
      );
    });

    test('does not duplicate an already recovered draft', () async {
      final startedAt = DateTime(2026, 9, 14, 9, 30);
      const recoveredPath = '/capture/interrupted_recovered.wav';
      final recorder = _FakeCaptureAudioRecorder(
        pendingRecovery: CaptureRecordingRecovery(
          kind: CaptureRecordingRecoveryKind.recovered,
          audioPath: recoveredPath,
          startedAt: startedAt,
        ),
      );
      var insertCalls = 0;
      final repository = CaptureRepository(
        audioRecorderService: recorder,
        getCaptureDraftByAudioPath: (_) async => CaptureDraft(
          id: 7,
          audioPath: recoveredPath,
          createdAt: startedAt,
          updatedAt: startedAt,
        ),
        insertCaptureDraft: (draft) async {
          insertCalls++;
          return 42;
        },
      );
      addTearDown(repository.dispose);

      final outcome = await repository.recoverPendingRecording();

      expect(outcome, CaptureRecordingRecoveryOutcome.recovered);
      expect(insertCalls, 0);
      expect(recorder.clearPendingCalls, 1);
    });

    test('reports an unavailable interrupted recording once', () async {
      final startedAt = DateTime(2026, 9, 14, 9, 30);
      final recorder = _FakeCaptureAudioRecorder(
        pendingRecovery: CaptureRecordingRecovery(
          kind: CaptureRecordingRecoveryKind.unavailable,
          audioPath: '/capture/empty.wav',
          startedAt: startedAt,
        ),
      );
      final repository = CaptureRepository(audioRecorderService: recorder);
      addTearDown(repository.dispose);

      final outcome = await repository.recoverPendingRecording();

      expect(outcome, CaptureRecordingRecoveryOutcome.unavailable);
      expect(
        repository.currentRecordingState.phase,
        CaptureRecordingPhase.interrupted,
      );
      expect(recorder.clearPendingCalls, 1);
    });
  });
}

class _FakeCaptureAudioRecorder implements CaptureAudioRecorder {
  _FakeCaptureAudioRecorder({
    this.permissionGranted = true,
    this.startError,
    this.stopPath = '/capture/test.wav',
    this.pendingRecovery,
  });

  final bool permissionGranted;
  final Object? startError;
  final String? stopPath;
  CaptureRecordingRecovery? pendingRecovery;

  int startCalls = 0;
  int stopCalls = 0;
  int clearPendingCalls = 0;

  final StreamController<String> _externallyStoppedRecordingPathsController =
      StreamController<String>.broadcast(sync: true);

  @override
  Stream<String> get externallyStoppedRecordingPaths =>
      _externallyStoppedRecordingPathsController.stream;

  void stopExternally([String audioPath = '/capture/test.wav']) {
    _externallyStoppedRecordingPathsController.add(audioPath);
  }

  @override
  Future<bool> requestPermission() async {
    return permissionGranted;
  }

  @override
  Future<String> startRecordingAfterPermissionGranted() async {
    startCalls++;

    if (startError != null) {
      throw startError!;
    }

    return '/capture/test.wav';
  }

  @override
  Future<String?> stopRecording() async {
    stopCalls++;
    return stopPath;
  }

  @override
  Future<CaptureRecordingRecovery?> recoverPendingRecording() async {
    return pendingRecovery;
  }

  @override
  Future<void> clearPendingRecording() async {
    clearPendingCalls++;
    pendingRecovery = null;
  }

  @override
  Future<void> dispose() {
    return _externallyStoppedRecordingPathsController.close();
  }
}

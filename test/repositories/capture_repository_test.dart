import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/capture_recording_state.dart';
import 'package:noahs_ark_app/repositories/capture_repository.dart';
import 'package:noahs_ark_app/services/audio_recorder_service.dart';
import 'package:noahs_ark_app/models/capture_draft.dart';
import 'package:noahs_ark_app/models/capture_playback_state.dart';
import 'package:noahs_ark_app/services/audio_playback_service.dart';

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

    test('forwards audio levels from recorder', () async {
      final recorder = _FakeCaptureAudioRecorder();
      final repository = CaptureRepository(audioRecorderService: recorder);
      addTearDown(repository.dispose);

      final levels = <double>[];
      final subscription = repository.audioLevelDbfs.listen(levels.add);
      addTearDown(subscription.cancel);

      recorder.emitAudioLevel(-42.5);
      recorder.emitAudioLevel(-12);

      expect(levels, [-42.5, -12]);
      expect(
        repository.currentRecordingState.phase,
        CaptureRecordingPhase.idle,
      );
    });
  });

  group('CaptureRepository playback', () {
    late _FakeCaptureAudioPlayback playback;
    late CaptureRepository repository;

    setUp(() {
      playback = _FakeCaptureAudioPlayback();
      repository = CaptureRepository(
        audioRecorderService: _FakeCaptureAudioRecorder(),
        audioPlaybackService: playback,
      );
      addTearDown(repository.dispose);
    });

    test('stop waits for an in-flight play before returning', () async {
      const path = '/capture/a.wav';
      playback.playEntered = Completer<void>();
      playback.playGate = Completer<bool>();

      final toggleFuture = repository.togglePlayback(path);
      await playback.playEntered!.future;

      final stopFuture = repository.stopPlayback(audioPath: path);
      playback.playGate!.complete(true);

      expect(await toggleFuture, isFalse);
      await stopFuture;

      expect(repository.currentPlaybackState.phase, CapturePlaybackPhase.idle);
      expect(playback.commands.last, 'stop');
    });

    test('switching clips waits for an in-flight seek', () async {
      const first = '/capture/a.wav';
      const second = '/capture/b.wav';

      expect(await repository.togglePlayback(first), isTrue);
      playback.emitDuration(const Duration(seconds: 90));
      playback.seekEntered = Completer<void>();
      playback.seekGate = Completer<void>();

      final seekFuture = repository.seekPlayback(const Duration(seconds: 40));
      await playback.seekEntered!.future;

      final switchFuture = repository.togglePlayback(second);
      try {
        expect(playback.playedPaths, [first]);
        expect(playback.commands.last, 'seek-start');
      } finally {
        playback.seekGate!.complete();
      }

      await seekFuture;
      expect(await switchFuture, isTrue);
      expect(playback.playedPaths, [first, second]);
      expect(
        playback.commands.indexOf('seek-end'),
        lessThan(playback.commands.lastIndexOf('stop')),
      );
      expect(
        playback.commands.lastIndexOf('stop'),
        lessThan(playback.commands.lastIndexOf('play-start')),
      );
      expect(repository.currentPlaybackState.audioPath, second);
      expect(repository.currentPlaybackState.position, Duration.zero);
    });

    test('stop waits for an in-flight seek before returning', () async {
      const path = '/capture/a.wav';

      expect(await repository.togglePlayback(path), isTrue);
      playback.emitDuration(const Duration(seconds: 90));
      playback.seekEntered = Completer<void>();
      playback.seekGate = Completer<void>();

      final seekFuture = repository.seekPlayback(const Duration(seconds: 40));
      await playback.seekEntered!.future;

      final stopFuture = repository.stopPlayback(audioPath: path);
      try {
        expect(
          repository.currentPlaybackState.phase,
          CapturePlaybackPhase.idle,
        );
        expect(playback.commands.last, 'seek-start');
      } finally {
        playback.seekGate!.complete();
      }

      await seekFuture;
      await stopFuture;
      expect(playback.commands.last, 'stop');
      expect(repository.currentPlaybackState.phase, CapturePlaybackPhase.idle);
      expect(repository.currentPlaybackState.audioPath, isNull);
    });

    test('pause and resume retain position; seeking stays in bounds', () async {
      const path = '/capture/a.wav';

      expect(await repository.togglePlayback(path), isTrue);
      playback.emitDuration(const Duration(seconds: 120));
      playback.emitPosition(const Duration(seconds: 30));

      expect(repository.currentPlaybackState.isPlaying, isTrue);
      expect(
        repository.currentPlaybackState.position,
        const Duration(seconds: 30),
      );

      await repository.togglePlayback(path);
      expect(repository.currentPlaybackState.isPaused, isTrue);
      expect(
        repository.currentPlaybackState.position,
        const Duration(seconds: 30),
      );
      expect(playback.pauseCalls, 1);

      await repository.togglePlayback(path);
      expect(repository.currentPlaybackState.isPlaying, isTrue);
      expect(playback.resumeCalls, 1);

      await repository.seekPlayback(const Duration(seconds: 200));
      expect(playback.seekTargets.last, const Duration(seconds: 120));

      await repository.seekPlayback(const Duration(seconds: -5));
      expect(playback.seekTargets.last, Duration.zero);
    });

    test(
      'switching clips resets progress and stops only the matching path',
      () async {
        const first = '/capture/a.wav';
        const second = '/capture/b.wav';

        await repository.togglePlayback(first);
        playback.emitDuration(const Duration(seconds: 90));
        playback.emitPosition(const Duration(seconds: 40));

        await repository.togglePlayback(second);

        expect(playback.playedPaths, [first, second]);
        expect(repository.currentPlaybackState.audioPath, second);
        expect(repository.currentPlaybackState.position, Duration.zero);
        expect(repository.currentPlaybackState.duration, Duration.zero);

        final stopCalls = playback.stopCalls;
        await repository.stopPlayback(audioPath: first);
        expect(playback.stopCalls, stopCalls);
        expect(repository.currentPlaybackState.audioPath, second);

        await repository.stopPlayback(audioPath: second);
        expect(playback.stopCalls, stopCalls + 1);
        expect(
          repository.currentPlaybackState.phase,
          CapturePlaybackPhase.idle,
        );
      },
    );

    test('completion during loading does not leave playback active', () async {
      const path = '/capture/short.wav';
      playback.playEntered = Completer<void>();
      playback.playGate = Completer<bool>();

      final toggleFuture = repository.togglePlayback(path);
      await playback.playEntered!.future;

      try {
        expect(
          repository.currentPlaybackState.phase,
          CapturePlaybackPhase.loading,
        );
        playback.emitComplete();
      } finally {
        playback.playGate!.complete(true);
      }

      await toggleFuture;
      expect(repository.currentPlaybackState.phase, CapturePlaybackPhase.idle);
    });

    test('completion clears the active playback state', () async {
      await repository.togglePlayback('/capture/a.wav');
      playback.emitDuration(const Duration(seconds: 10));
      playback.emitPosition(const Duration(seconds: 9));

      playback.emitComplete();

      expect(repository.currentPlaybackState.phase, CapturePlaybackPhase.idle);
      expect(repository.currentPlaybackState.audioPath, isNull);
      expect(repository.currentPlaybackState.position, Duration.zero);
      expect(repository.currentPlaybackState.duration, Duration.zero);
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

  final StreamController<double> _audioLevelDbfsController =
      StreamController<double>.broadcast(sync: true);

  @override
  Stream<double> get audioLevelDbfs => _audioLevelDbfsController.stream;

  void emitAudioLevel(double value) {
    _audioLevelDbfsController.add(value);
  }

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
  Future<void> dispose() async {
    await _externallyStoppedRecordingPathsController.close();
    await _audioLevelDbfsController.close();
  }
}

class _FakeCaptureAudioPlayback implements CaptureAudioPlayback {
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final _durations = StreamController<Duration>.broadcast(sync: true);
  final _completions = StreamController<void>.broadcast(sync: true);

  final List<String> playedPaths = [];
  final List<Duration> seekTargets = [];
  int pauseCalls = 0;
  int resumeCalls = 0;
  int stopCalls = 0;

  Completer<void>? playEntered;
  Completer<bool>? playGate;
  Completer<void>? seekEntered;
  Completer<void>? seekGate;
  final List<String> commands = [];

  void emitPosition(Duration position) => _positions.add(position);

  void emitDuration(Duration duration) => _durations.add(duration);

  void emitComplete() => _completions.add(null);

  @override
  Stream<Duration> get onPositionChanged => _positions.stream;

  @override
  Stream<Duration> get onDurationChanged => _durations.stream;

  @override
  Stream<void> get onPlayerComplete => _completions.stream;

  @override
  Future<bool> play(String filePath) async {
    playedPaths.add(filePath);
    commands.add('play-start');
    playEntered?.complete();

    final gate = playGate;
    final result = gate == null ? true : await gate.future;

    commands.add('play-end');
    return result;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
  }

  @override
  Future<void> seek(Duration position) async {
    seekTargets.add(position);
    commands.add('seek-start');
    final entered = seekEntered;
    if (entered != null && !entered.isCompleted) {
      entered.complete();
    }

    final gate = seekGate;
    if (gate != null) {
      await gate.future;
    }

    commands.add('seek-end');
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    commands.add('stop');
  }

  @override
  Future<void> dispose() async {
    await _positions.close();
    await _durations.close();
    await _completions.close();
  }
}

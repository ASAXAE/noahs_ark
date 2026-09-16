import 'dart:async';
import 'package:flutter/foundation.dart';

import '../database/ark_database.dart';
import '../models/capture_draft.dart';
import '../models/capture_recording_state.dart';
import '../models/capture_playback_state.dart';
import '../services/audio_playback_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/foreground_audio_recorder_service.dart';
import '../services/transcription_model_manager.dart';
import '../services/transcription_worker.dart';

enum CaptureRecordingRecoveryOutcome { none, active, recovered, unavailable }

class CaptureRepository {
  CaptureRepository({
    CaptureAudioRecorder? audioRecorderService,
    CaptureAudioPlayback? audioPlaybackService,
    TranscriptionModelManager? transcriptionModelManager,
    Future<int> Function(CaptureDraft draft)? insertCaptureDraft,
    Future<CaptureDraft?> Function(int id)? getCaptureDraft,
    Future<CaptureDraft?> Function(String audioPath)?
    getCaptureDraftByAudioPath,
    Future<void> Function(CaptureDraft draft)? updateCaptureDraft,
    Future<int> Function()? recoverInterruptedCaptureDrafts,
  }) : _audioRecorderService =
           audioRecorderService ?? ForegroundAudioRecorderService(),
       _audioPlaybackService = audioPlaybackService,
       _transcriptionModelManager =
           transcriptionModelManager ?? TranscriptionModelManager(),
       _insertCaptureDraft =
           insertCaptureDraft ?? ArkDatabase.instance.insertCaptureDraft,
       _getCaptureDraft =
           getCaptureDraft ?? ArkDatabase.instance.getCaptureDraft,
       _getCaptureDraftByAudioPath =
           getCaptureDraftByAudioPath ??
           ArkDatabase.instance.getCaptureDraftByAudioPath,
       _updateCaptureDraft =
           updateCaptureDraft ?? ArkDatabase.instance.updateCaptureDraft,
       _recoverInterruptedCaptureDrafts =
           recoverInterruptedCaptureDrafts ??
           ArkDatabase.instance.recoverInterruptedCaptureDrafts {
    _externallyStoppedRecordingSubscription = _audioRecorderService
        .externallyStoppedRecordingPaths
        .listen((audioPath) {
          unawaited(_saveExternallyStoppedRecording(audioPath));
        });
  }

  final CaptureAudioRecorder _audioRecorderService;

  CaptureAudioPlayback? _audioPlaybackService;
  StreamSubscription<Duration>? _playbackPositionSubscription;
  StreamSubscription<Duration>? _playbackDurationSubscription;
  StreamSubscription<void>? _playbackCompleteSubscription;
  bool _playbackSubscriptionsReady = false;
  bool _playbackActionInProgress = false;

  int _playbackGeneration = 0;
  int? _startingPlaybackGeneration;
  int? _completedWhileStartingGeneration;
  Completer<void>? _toggleSettled;
  Completer<void>? _seekSettled;
  bool _stopInProgress = false;

  CaptureAudioPlayback get _audioPlayback {
    if (_disposed) {
      throw StateError('CaptureRepository 已释放');
    }

    final playback = _audioPlaybackService ??= AudioPlaybackService();
    _ensurePlaybackSubscriptions(playback);
    return playback;
  }

  late final StreamSubscription<String> _externallyStoppedRecordingSubscription;
  final Future<int> Function(CaptureDraft draft) _insertCaptureDraft;

  final TranscriptionModelManager _transcriptionModelManager;
  final Future<CaptureDraft?> Function(int id) _getCaptureDraft;
  final Future<CaptureDraft?> Function(String audioPath)
  _getCaptureDraftByAudioPath;
  final Future<void> Function(CaptureDraft draft) _updateCaptureDraft;
  final Future<int> Function() _recoverInterruptedCaptureDrafts;

  TranscriptionWorker? _transcriptionWorker;

  final ValueNotifier<CaptureRecordingState> _recordingState = ValueNotifier(
    const CaptureRecordingState.idle(),
  );

  final ValueNotifier<CapturePlaybackState> _playbackState = ValueNotifier(
    const CapturePlaybackState.idle(),
  );

  bool _disposed = false;

  Stream<double> get audioLevelDbfs => _audioRecorderService.audioLevelDbfs;

  ValueListenable<CaptureRecordingState> get recordingState => _recordingState;

  CaptureRecordingState get currentRecordingState => _recordingState.value;

  ValueListenable<CapturePlaybackState> get playbackState => _playbackState;

  CapturePlaybackState get currentPlaybackState => _playbackState.value;

  Future<bool> togglePlayback(String audioPath) async {
    if (_disposed ||
        _playbackActionInProgress ||
        _stopInProgress ||
        audioPath.isEmpty) {
      return false;
    }

    _playbackActionInProgress = true;
    final generation = ++_playbackGeneration;
    final settled = Completer<void>();
    _toggleSettled = settled;

    try {
      final pendingSeek = _seekSettled?.future;
      if (pendingSeek != null) {
        await pendingSeek;
      }
      if (_disposed || generation != _playbackGeneration) {
        return false;
      }

      final player = _audioPlayback;
      final current = currentPlaybackState;

      if (current.audioPath == audioPath && current.isPlaying) {
        await player.pause();

        if (_disposed || generation != _playbackGeneration) {
          return false;
        }

        final latest = currentPlaybackState;
        if (latest.audioPath == audioPath) {
          _setPlaybackState(
            latest.copyWith(phase: CapturePlaybackPhase.paused),
          );
        }
        return true;
      }

      if (current.audioPath == audioPath && current.isPaused) {
        await player.resume();

        if (_disposed || generation != _playbackGeneration) {
          return false;
        }

        final latest = currentPlaybackState;
        if (latest.audioPath == audioPath) {
          _setPlaybackState(
            latest.copyWith(phase: CapturePlaybackPhase.playing),
          );
        }
        return true;
      }

      _setPlaybackState(CapturePlaybackState.loading(audioPath: audioPath));

      await player.stop();

      if (_disposed ||
          generation != _playbackGeneration ||
          currentPlaybackState.audioPath != audioPath) {
        return false;
      }

      _startingPlaybackGeneration = generation;
      _completedWhileStartingGeneration = null;
      final started = await player.play(audioPath);

      if (_disposed ||
          generation != _playbackGeneration ||
          currentPlaybackState.audioPath != audioPath) {
        return false;
      }

      if (!started) {
        _setPlaybackState(const CapturePlaybackState.idle());
        return false;
      }

      if (_completedWhileStartingGeneration == generation) {
        _setPlaybackState(const CapturePlaybackState.idle());
        return true;
      }

      _setPlaybackState(
        currentPlaybackState.copyWith(phase: CapturePlaybackPhase.playing),
      );
      return true;
    } catch (_) {
      if (!_disposed && generation == _playbackGeneration) {
        _setPlaybackState(const CapturePlaybackState.idle());
      }
      rethrow;
    } finally {
      if (_startingPlaybackGeneration == generation) {
        _startingPlaybackGeneration = null;
      }
      if (_completedWhileStartingGeneration == generation) {
        _completedWhileStartingGeneration = null;
      }
      _playbackActionInProgress = false;
      if (identical(_toggleSettled, settled)) {
        _toggleSettled = null;
      }
      settled.complete();
    }
  }

  Future<void> seekPlayback(Duration position) async {
    final current = currentPlaybackState;

    if (_disposed ||
        _playbackActionInProgress ||
        _stopInProgress ||
        _seekSettled != null ||
        !current.hasActivePlayback ||
        current.duration.inMilliseconds <= 0) {
      return;
    }

    final audioPath = current.audioPath;
    final target = _clampPlaybackPosition(position, current.duration);
    final generation = _playbackGeneration;
    final settled = Completer<void>();
    _seekSettled = settled;

    try {
      await _audioPlayback.seek(target);

      final latest = currentPlaybackState;
      if (!_disposed &&
          generation == _playbackGeneration &&
          latest.audioPath == audioPath) {
        _setPlaybackState(latest.copyWith(position: target));
      }
    } finally {
      if (identical(_seekSettled, settled)) {
        _seekSettled = null;
      }
      settled.complete();
    }
  }

  Future<void> stopPlayback({String? audioPath}) async {
    final current = currentPlaybackState;

    if (_disposed || !current.hasActivePlayback || _stopInProgress) {
      return;
    }

    if (audioPath != null && current.audioPath != audioPath) {
      return;
    }

    _stopInProgress = true;
    ++_playbackGeneration;
    _setPlaybackState(const CapturePlaybackState.idle());

    final pendingToggle = _toggleSettled?.future;
    final pendingSeek = _seekSettled?.future;

    try {
      if (pendingToggle != null) {
        await pendingToggle;
      }

      if (pendingSeek != null) {
        await pendingSeek;
      }

      if (!_disposed) {
        await _audioPlayback.stop();
      }
    } finally {
      _stopInProgress = false;
    }
  }

  Future<bool> startRecording() async {
    if (_disposed || !currentRecordingState.canStart) {
      return false;
    }

    _setRecordingState(const CaptureRecordingState.requestingPermission());

    try {
      final hasPermission = await _audioRecorderService.requestPermission();

      if (!hasPermission) {
        _setRecordingState(
          const CaptureRecordingState.failed(
            failure: CaptureRecordingFailure.permissionDenied,
          ),
        );
        return false;
      }

      _setRecordingState(const CaptureRecordingState.starting());

      final startedAt = DateTime.now();
      final audioPath = await _audioRecorderService
          .startRecordingAfterPermissionGranted();

      _setRecordingState(
        CaptureRecordingState.recording(
          audioPath: audioPath,
          startedAt: startedAt,
        ),
      );

      return true;
    } catch (_) {
      _setRecordingState(
        const CaptureRecordingState.failed(
          failure: CaptureRecordingFailure.startFailed,
        ),
      );
      rethrow;
    }
  }

  Future<int?> stopAndSaveRecording() {
    return _stopAndSaveRecording(interrupted: false);
  }

  Future<int?> stopRecordingForInterruption() {
    return _stopAndSaveRecording(interrupted: true);
  }

  Future<CaptureRecordingRecoveryOutcome> recoverPendingRecording() async {
    if (_disposed || !currentRecordingState.canStart) {
      return CaptureRecordingRecoveryOutcome.none;
    }

    _setRecordingState(const CaptureRecordingState.starting());

    try {
      final recovery = await _audioRecorderService.recoverPendingRecording();

      if (recovery == null) {
        _setRecordingState(const CaptureRecordingState.idle());
        return CaptureRecordingRecoveryOutcome.none;
      }

      if (recovery.kind == CaptureRecordingRecoveryKind.active) {
        _setRecordingState(
          CaptureRecordingState.recording(
            audioPath: recovery.audioPath,
            startedAt: recovery.startedAt,
          ),
        );
        return CaptureRecordingRecoveryOutcome.active;
      }

      if (recovery.kind == CaptureRecordingRecoveryKind.unavailable) {
        await _clearPendingRecordingBestEffort();
        _setRecordingState(
          CaptureRecordingState.interrupted(
            audioPath: recovery.audioPath,
            startedAt: recovery.startedAt,
          ),
        );
        return CaptureRecordingRecoveryOutcome.unavailable;
      }

      final existingDraft = await _getCaptureDraftByAudioPath(
        recovery.audioPath,
      );

      if (existingDraft == null) {
        await _saveDraft(recovery.audioPath, createdAt: recovery.startedAt);
      }

      await _clearPendingRecordingBestEffort();
      _setRecordingState(const CaptureRecordingState.idle());
      return CaptureRecordingRecoveryOutcome.recovered;
    } catch (_) {
      _setRecordingState(const CaptureRecordingState.interrupted());
      rethrow;
    }
  }

  Future<void> _saveExternallyStoppedRecording(String audioPath) async {
    final recording = currentRecordingState;
    final startedAt = recording.startedAt;

    if (_disposed ||
        !recording.canStop ||
        recording.audioPath != audioPath ||
        startedAt == null) {
      return;
    }

    _setRecordingState(
      CaptureRecordingState.stopping(
        audioPath: audioPath,
        startedAt: startedAt,
      ),
    );

    try {
      await _saveDraft(audioPath, createdAt: startedAt);
      await _clearPendingRecordingBestEffort();
      _setRecordingState(const CaptureRecordingState.idle());
    } catch (_) {
      _setRecordingState(
        CaptureRecordingState.failed(
          failure: CaptureRecordingFailure.saveFailed,
          audioPath: audioPath,
          startedAt: startedAt,
        ),
      );
    }
  }

  Future<int?> _stopAndSaveRecording({required bool interrupted}) async {
    final recording = currentRecordingState;
    final audioPath = recording.audioPath;
    final startedAt = recording.startedAt;

    if (_disposed ||
        !recording.canStop ||
        audioPath == null ||
        startedAt == null) {
      return null;
    }

    if (interrupted) {
      markRecordingInterrupted();
    }

    _setRecordingState(
      CaptureRecordingState.stopping(
        audioPath: audioPath,
        startedAt: startedAt,
      ),
    );

    String? stoppedAudioPath;

    try {
      stoppedAudioPath = await _audioRecorderService.stopRecording();
    } catch (_) {
      _setRecordingState(
        CaptureRecordingState.failed(
          failure: CaptureRecordingFailure.stopFailed,
          audioPath: audioPath,
          startedAt: startedAt,
        ),
      );
      rethrow;
    }

    if (stoppedAudioPath == null) {
      _setRecordingState(
        CaptureRecordingState.failed(
          failure: CaptureRecordingFailure.stopFailed,
          audioPath: audioPath,
          startedAt: startedAt,
        ),
      );
      return null;
    }

    try {
      final draftId = await _saveDraft(stoppedAudioPath, createdAt: startedAt);
      await _clearPendingRecordingBestEffort();
      _setRecordingState(const CaptureRecordingState.idle());
      return draftId;
    } catch (_) {
      _setRecordingState(
        CaptureRecordingState.failed(
          failure: CaptureRecordingFailure.saveFailed,
          audioPath: stoppedAudioPath,
          startedAt: startedAt,
        ),
      );
      rethrow;
    }
  }

  void markRecordingInterrupted() {
    final recording = currentRecordingState;

    if (!recording.isRecording) {
      return;
    }

    _setRecordingState(
      CaptureRecordingState.interrupted(
        audioPath: recording.audioPath,
        startedAt: recording.startedAt,
      ),
    );
  }

  Future<CaptureDraft?> getCaptureDraft(int id) {
    return _getCaptureDraft(id);
  }

  Future<int> recoverInterruptedTranscriptions() {
    return _recoverInterruptedCaptureDrafts();
  }

  Future<bool> isTranscriptionModelInstalled() {
    return _transcriptionModelManager.isInstalled();
  }

  Future<TranscriptionModelFiles> getTranscriptionModelFiles() {
    return _transcriptionModelManager.getLocalFiles();
  }

  Future<TranscriptionModelFiles> downloadTranscriptionModel() {
    return _transcriptionModelManager.download();
  }

  Future<String> transcribeRecording({
    required String audioPath,
    required TranscriptionModelFiles modelFiles,
  }) {
    _transcriptionWorker ??= TranscriptionWorker(
      modelPath: modelFiles.modelPath,
      tokensPath: modelFiles.tokensPath,
    );

    return _transcriptionWorker!.transcribeFile(audioPath);
  }

  Future<CaptureDraft> transcribeDraft({
    required CaptureDraft draft,
    required TranscriptionModelFiles modelFiles,
  }) async {
    final transcribingDraft = draft.copyWith(
      transcriptionStatus: CaptureTranscriptionStatus.transcribing,
      clearTranscriptionError: true,
      updatedAt: DateTime.now(),
    );

    try {
      await _updateCaptureDraft(transcribingDraft);

      final transcript = await transcribeRecording(
        audioPath: draft.audioPath,
        modelFiles: modelFiles,
      );

      final completedDraft = transcribingDraft.copyWith(
        transcript: transcript,
        transcriptionStatus: CaptureTranscriptionStatus.completed,
        clearTranscriptionError: true,
        updatedAt: DateTime.now(),
      );

      await _updateCaptureDraft(completedDraft);
      return completedDraft;
    } catch (error) {
      final failedDraft = transcribingDraft.copyWith(
        transcriptionStatus: CaptureTranscriptionStatus.failed,
        transcriptionError: error.toString(),
        updatedAt: DateTime.now(),
      );

      await _updateCaptureDraft(failedDraft);
      rethrow;
    }
  }

  Future<int> _saveDraft(String audioPath, {DateTime? createdAt}) {
    final now = DateTime.now();

    return _insertCaptureDraft(
      CaptureDraft(
        audioPath: audioPath,
        createdAt: createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _clearPendingRecordingBestEffort() async {
    try {
      await _audioRecorderService.clearPendingRecording();
    } catch (error) {
      debugPrint('清理待恢复录音标记失败：$error');
    }
  }

  void _ensurePlaybackSubscriptions(CaptureAudioPlayback playback) {
    if (_playbackSubscriptionsReady) {
      return;
    }

    _playbackSubscriptionsReady = true;

    _playbackPositionSubscription = playback.onPositionChanged.listen(
      _handlePlaybackPositionChanged,
    );
    _playbackDurationSubscription = playback.onDurationChanged.listen(
      _handlePlaybackDurationChanged,
    );
    _playbackCompleteSubscription = playback.onPlayerComplete.listen((_) {
      if (_disposed) return;

      final current = currentPlaybackState;
      if (!current.hasActivePlayback) return;

      if (current.isLoading) {
        if (_startingPlaybackGeneration == _playbackGeneration) {
          _completedWhileStartingGeneration = _playbackGeneration;
        }
        return;
      }

      _setPlaybackState(const CapturePlaybackState.idle());
    });
  }

  void _handlePlaybackPositionChanged(Duration position) {
    if (_disposed) {
      return;
    }

    final current = currentPlaybackState;
    if (!current.hasActivePlayback) {
      return;
    }

    _setPlaybackState(
      current.copyWith(
        position: _clampPlaybackPosition(position, current.duration),
      ),
    );
  }

  void _handlePlaybackDurationChanged(Duration duration) {
    if (_disposed) {
      return;
    }

    final current = currentPlaybackState;
    if (!current.hasActivePlayback) {
      return;
    }

    final safeDuration = duration.isNegative ? Duration.zero : duration;

    _setPlaybackState(
      current.copyWith(
        duration: safeDuration,
        position: _clampPlaybackPosition(current.position, safeDuration),
      ),
    );
  }

  Duration _clampPlaybackPosition(Duration position, Duration duration) {
    if (position.isNegative) {
      return Duration.zero;
    }

    if (duration.inMilliseconds > 0 &&
        position.inMilliseconds > duration.inMilliseconds) {
      return duration;
    }

    return position;
  }

  void _setPlaybackState(CapturePlaybackState state) {
    if (!_disposed) {
      _playbackState.value = state;
    }
  }

  void _setRecordingState(CaptureRecordingState state) {
    if (!_disposed) {
      _recordingState.value = state;
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await _playbackPositionSubscription?.cancel();
    await _playbackDurationSubscription?.cancel();
    await _playbackCompleteSubscription?.cancel();
    await _externallyStoppedRecordingSubscription.cancel();
    await _transcriptionWorker?.dispose();
    _transcriptionModelManager.dispose();
    await _audioRecorderService.dispose();
    final playback = _audioPlaybackService;
    if (playback != null) {
      await _toggleSettled?.future;
      await _seekSettled?.future;
      await playback.dispose();
    }

    _playbackState.dispose();
    _recordingState.dispose();
  }
}

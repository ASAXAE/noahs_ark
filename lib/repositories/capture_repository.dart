import 'package:flutter/foundation.dart';

import '../database/ark_database.dart';
import '../models/capture_draft.dart';
import '../models/capture_recording_state.dart';
import '../services/audio_recorder_service.dart';
import '../services/foreground_audio_recorder_service.dart';
import '../services/transcription_model_manager.dart';
import '../services/transcription_worker.dart';

class CaptureRepository {
  CaptureRepository({
    CaptureAudioRecorder? audioRecorderService,
    TranscriptionModelManager? transcriptionModelManager,
    Future<int> Function(CaptureDraft draft)? insertCaptureDraft,
    Future<CaptureDraft?> Function(int id)? getCaptureDraft,
    Future<void> Function(CaptureDraft draft)? updateCaptureDraft,
    Future<int> Function()? recoverInterruptedCaptureDrafts,
  }) : _audioRecorderService =
           audioRecorderService ?? ForegroundAudioRecorderService(),
       _transcriptionModelManager =
           transcriptionModelManager ?? TranscriptionModelManager(),
       _insertCaptureDraft =
           insertCaptureDraft ?? ArkDatabase.instance.insertCaptureDraft,
       _getCaptureDraft =
           getCaptureDraft ?? ArkDatabase.instance.getCaptureDraft,
       _updateCaptureDraft =
           updateCaptureDraft ?? ArkDatabase.instance.updateCaptureDraft,
       _recoverInterruptedCaptureDrafts =
           recoverInterruptedCaptureDrafts ??
           ArkDatabase.instance.recoverInterruptedCaptureDrafts;

  final CaptureAudioRecorder _audioRecorderService;
  final Future<int> Function(CaptureDraft draft) _insertCaptureDraft;

  final TranscriptionModelManager _transcriptionModelManager;
  final Future<CaptureDraft?> Function(int id) _getCaptureDraft;
  final Future<void> Function(CaptureDraft draft) _updateCaptureDraft;
  final Future<int> Function() _recoverInterruptedCaptureDrafts;

  TranscriptionWorker? _transcriptionWorker;

  final ValueNotifier<CaptureRecordingState> _recordingState = ValueNotifier(
    const CaptureRecordingState.idle(),
  );

  bool _disposed = false;

  ValueListenable<CaptureRecordingState> get recordingState => _recordingState;

  CaptureRecordingState get currentRecordingState => _recordingState.value;

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
      final draftId = await _saveDraft(stoppedAudioPath);
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

  Future<int> _saveDraft(String audioPath) {
    final now = DateTime.now();

    return _insertCaptureDraft(
      CaptureDraft(audioPath: audioPath, createdAt: now, updatedAt: now),
    );
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
    await _transcriptionWorker?.dispose();
    _transcriptionModelManager.dispose();
    await _audioRecorderService.dispose();
    _recordingState.dispose();
  }
}

import '../database/ark_database.dart';
import '../models/capture_draft.dart';
import '../services/audio_playback_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/transcription_model_manager.dart';
import '../services/sherpa_transcription_service.dart';

class CaptureController {
  final _audioRecorderService = AudioRecorderService();
  final _audioPlaybackService = AudioPlaybackService();
  final _transcriptionModelManager = TranscriptionModelManager();
  SherpaTranscriptionService? _transcriptionService;

  Future<String?> startRecording() {
    return _audioRecorderService.startRecording();
  }

  Future<String?> stopRecording() {
    return _audioRecorderService.stopRecording();
  }

  Future<int> saveDraft(String audioPath) {
    final now = DateTime.now();

    final draft = CaptureDraft(
      audioPath: audioPath,
      createdAt: now,
      updatedAt: now,
    );

    return ArkDatabase.instance.insertCaptureDraft(draft);
  }

  Future<bool> playRecording(String filePath) {
    return _audioPlaybackService.play(filePath);
  }

  Future<bool> deleteRecording(String filePath) async {
    await _audioPlaybackService.stop();

    final deleted = await _audioRecorderService.deleteRecording(filePath);

    if (deleted) {
      await ArkDatabase.instance.deleteCaptureDraftByAudioPath(filePath);
    }

    return deleted;
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
    _transcriptionService ??= SherpaTranscriptionService(
      modelPath: modelFiles.modelPath,
      tokensPath: modelFiles.tokensPath,
    );

    return _transcriptionService!.transcribeFile(audioPath);
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
      await ArkDatabase.instance.updateCaptureDraft(transcribingDraft);

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

      await ArkDatabase.instance.updateCaptureDraft(completedDraft);

      return completedDraft;
    } catch (error) {
      final failedDraft = transcribingDraft.copyWith(
        transcriptionStatus: CaptureTranscriptionStatus.failed,
        transcriptionError: error.toString(),
        updatedAt: DateTime.now(),
      );

      await ArkDatabase.instance.updateCaptureDraft(failedDraft);
      rethrow;
    }
  }

  Future<void> dispose() async {
    _transcriptionService?.dispose();
    _transcriptionModelManager.dispose();
    await _audioPlaybackService.dispose();
    await _audioRecorderService.dispose();
  }
}

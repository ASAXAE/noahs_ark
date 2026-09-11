enum CaptureRecordingPhase {
  idle,
  requestingPermission,
  starting,
  recording,
  stopping,
  interrupted,
  failed,
}

enum CaptureRecordingFailure {
  permissionDenied,
  startFailed,
  stopFailed,
  saveFailed,
}

class CaptureRecordingState {
  const CaptureRecordingState.idle()
    : phase = CaptureRecordingPhase.idle,
      audioPath = null,
      startedAt = null,
      failure = null;

  const CaptureRecordingState.requestingPermission()
    : phase = CaptureRecordingPhase.requestingPermission,
      audioPath = null,
      startedAt = null,
      failure = null;

  const CaptureRecordingState.starting()
    : phase = CaptureRecordingPhase.starting,
      audioPath = null,
      startedAt = null,
      failure = null;

  const CaptureRecordingState.recording({
    required String audioPath,
    required DateTime startedAt,
  }) : phase = CaptureRecordingPhase.recording,
       audioPath = audioPath,
       startedAt = startedAt,
       failure = null;

  const CaptureRecordingState.stopping({
    required String audioPath,
    required DateTime startedAt,
  }) : phase = CaptureRecordingPhase.stopping,
       audioPath = audioPath,
       startedAt = startedAt,
       failure = null;

  const CaptureRecordingState.interrupted({this.audioPath, this.startedAt})
    : phase = CaptureRecordingPhase.interrupted,
      failure = null;

  const CaptureRecordingState.failed({
    required CaptureRecordingFailure failure,
    this.audioPath,
    this.startedAt,
  }) : phase = CaptureRecordingPhase.failed,
       failure = failure;

  final CaptureRecordingPhase phase;
  final String? audioPath;
  final DateTime? startedAt;
  final CaptureRecordingFailure? failure;

  bool get isRecording => phase == CaptureRecordingPhase.recording;

  bool get hasActiveRecording =>
      phase == CaptureRecordingPhase.recording ||
      phase == CaptureRecordingPhase.stopping;

  bool get isActionInProgress =>
      phase == CaptureRecordingPhase.requestingPermission ||
      phase == CaptureRecordingPhase.starting ||
      phase == CaptureRecordingPhase.stopping;

  bool get canStart =>
      phase == CaptureRecordingPhase.idle ||
      phase == CaptureRecordingPhase.interrupted ||
      phase == CaptureRecordingPhase.failed;

  bool get canStop => phase == CaptureRecordingPhase.recording;
}

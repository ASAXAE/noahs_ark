enum CapturePlaybackPhase { idle, loading, playing, paused }

class CapturePlaybackState {
  const CapturePlaybackState._({
    required this.phase,
    required this.audioPath,
    required this.position,
    required this.duration,
  });

  const CapturePlaybackState.idle()
    : phase = CapturePlaybackPhase.idle,
      audioPath = null,
      position = Duration.zero,
      duration = Duration.zero;

  const CapturePlaybackState.loading({required String this.audioPath})
    : phase = CapturePlaybackPhase.loading,
      position = Duration.zero,
      duration = Duration.zero;

  const CapturePlaybackState.playing({
    required String this.audioPath,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  }) : phase = CapturePlaybackPhase.playing;

  const CapturePlaybackState.paused({
    required String this.audioPath,
    required this.position,
    required this.duration,
  }) : phase = CapturePlaybackPhase.paused;

  final CapturePlaybackPhase phase;
  final String? audioPath;
  final Duration position;
  final Duration duration;

  bool get hasActivePlayback =>
      phase != CapturePlaybackPhase.idle && audioPath != null;

  bool get isPlaying => phase == CapturePlaybackPhase.playing;

  bool get isPaused => phase == CapturePlaybackPhase.paused;

  bool get isLoading => phase == CapturePlaybackPhase.loading;

  double get progress {
    final totalMilliseconds = duration.inMilliseconds;

    if (totalMilliseconds <= 0) {
      return 0;
    }

    return (position.inMilliseconds / totalMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  CapturePlaybackState copyWith({
    CapturePlaybackPhase? phase,
    String? audioPath,
    Duration? position,
    Duration? duration,
  }) {
    return CapturePlaybackState._(
      phase: phase ?? this.phase,
      audioPath: audioPath ?? this.audioPath,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }
}

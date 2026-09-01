enum CaptureTranscriptionStatus { pending, transcribing, completed, failed }

class CaptureDraft {
  const CaptureDraft({
    this.id,
    required this.audioPath,
    this.transcript,
    this.transcriptionStatus = CaptureTranscriptionStatus.pending,
    this.transcriptionError,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String audioPath;
  final String? transcript;
  final CaptureTranscriptionStatus transcriptionStatus;
  final String? transcriptionError;
  final DateTime createdAt;
  final DateTime updatedAt;

  CaptureDraft copyWith({
    String? transcript,
    CaptureTranscriptionStatus? transcriptionStatus,
    String? transcriptionError,
    bool clearTranscriptionError = false,
    DateTime? updatedAt,
  }) {
    return CaptureDraft(
      id: id,
      audioPath: audioPath,
      transcript: transcript ?? this.transcript,
      transcriptionStatus: transcriptionStatus ?? this.transcriptionStatus,
      transcriptionError: clearTranscriptionError
          ? null
          : transcriptionError ?? this.transcriptionError,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'audio_path': audioPath,
    'transcript': transcript,
    'transcription_status': transcriptionStatus.name,
    'transcription_error': transcriptionError,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory CaptureDraft.fromMap(Map<String, Object?> map) => CaptureDraft(
    id: map['id'] as int,
    audioPath: map['audio_path'] as String,
    transcript: map['transcript'] as String?,
    transcriptionStatus: CaptureTranscriptionStatus.values.byName(
      map['transcription_status'] as String,
    ),
    transcriptionError: map['transcription_error'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
  );
}

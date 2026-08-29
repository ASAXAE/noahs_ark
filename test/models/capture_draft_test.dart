import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/capture_draft.dart';

void main() {
  test('CaptureDraft can convert to a database map and back', () {
    final original = CaptureDraft(
      id: 7,
      audioPath: '/local/capture/draft-7.m4a',
      transcript: '突然想到的内容',
      transcriptionStatus: CaptureTranscriptionStatus.completed,
      createdAt: DateTime(2026, 8, 29, 9),
      updatedAt: DateTime(2026, 8, 29, 9, 5),
    );

    final restored = CaptureDraft.fromMap(original.toMap());

    expect(restored.id, original.id);
    expect(restored.audioPath, original.audioPath);
    expect(restored.transcript, original.transcript);
    expect(restored.transcriptionStatus, original.transcriptionStatus);
    expect(restored.transcriptionError, isNull);
    expect(restored.createdAt, original.createdAt);
    expect(restored.updatedAt, original.updatedAt);
  });

  test('CaptureDraft stays independent from Thought fields', () {
    final draft = CaptureDraft(
      id: 8,
      audioPath: '/local/capture/draft-8.m4a',
      transcriptionStatus: CaptureTranscriptionStatus.failed,
      transcriptionError: '暂时无法转写',
      createdAt: DateTime(2026, 8, 29, 10),
      updatedAt: DateTime(2026, 8, 29, 10, 1),
    );

    final map = draft.toMap();

    expect(map, isNot(contains('title')));
    expect(map, isNot(contains('tag')));
    expect(map['transcript'], isNull);
    expect(map['transcription_error'], '暂时无法转写');
  });
}

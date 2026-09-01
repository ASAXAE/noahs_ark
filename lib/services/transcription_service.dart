abstract interface class TranscriptionService {
  Future<String> transcribeFile(String audioPath);
}

class TranscriptionException implements Exception {
  const TranscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

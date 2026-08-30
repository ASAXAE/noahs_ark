import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  Future<bool> requestPermission() {
    return _recorder.hasPermission();
  }

  Future<String?> startRecording() async {
    final hasPermission = await requestPermission();

    if (!hasPermission) {
      return null;
    }

    final temporaryDirectory = await getTemporaryDirectory();
    final fileName = 'capture_${DateTime.now().microsecondsSinceEpoch}.m4a';
    final filePath = path.join(temporaryDirectory.path, fileName);

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: filePath,
    );

    return filePath;
  }

  Future<String?> stopRecording() {
    return _recorder.stop();
  }

  Future<void> dispose() {
    return _recorder.dispose();
  }
}

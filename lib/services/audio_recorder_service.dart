import 'dart:io';

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

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final audioDirectory = Directory(
      path.join(documentsDirectory.path, 'capture_audio'),
    );

    await audioDirectory.create(recursive: true);

    final fileName = 'capture_${DateTime.now().microsecondsSinceEpoch}.m4a';
    final filePath = path.join(audioDirectory.path, fileName);

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: filePath,
    );

    return filePath;
  }

  Future<String?> stopRecording() {
    return _recorder.stop();
  }

  Future<bool> deleteRecording(String filePath) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();

    final audioDirectoryPath = path.normalize(
      path.join(documentsDirectory.path, 'capture_audio'),
    );
    final normalizedFilePath = path.normalize(filePath);

    if (!path.isWithin(audioDirectoryPath, normalizedFilePath)) {
      return false;
    }

    final audioFile = File(normalizedFilePath);

    if (!await audioFile.exists()) {
      return false;
    }

    await audioFile.delete();
    return true;
  }

  Future<void> dispose() {
    return _recorder.dispose();
  }
}

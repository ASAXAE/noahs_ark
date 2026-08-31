import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();

  Future<bool> play(String filePath) async {
    final audioFile = File(filePath);

    if (!await audioFile.exists()) {
      return false;
    }

    await _player.play(DeviceFileSource(filePath));
    return true;
  }

  Future<void> stop() {
    return _player.stop();
  }

  Future<void> dispose() {
    return _player.dispose();
  }
}

import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart';

const foregroundRecordingAudioPathKey = 'foreground_recording_audio_path';
const foregroundRecordingStopCommand = 'foreground_recording_stop';

const foregroundRecordingMessageType = 'foreground_recording';
const foregroundRecordingStartedEvent = 'started';
const foregroundRecordingStoppedEvent = 'stopped';
const foregroundRecordingFailedEvent = 'failed';

@pragma('vm:entry-point')
void startForegroundRecordingCallback() {
  FlutterForegroundTask.setTaskHandler(ForegroundRecordingTaskHandler());
}

class ForegroundRecordingTaskHandler extends TaskHandler {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  String? _audioPath;
  Future<void>? _stopFuture;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final audioPath = await FlutterForegroundTask.getData<String>(
      key: foregroundRecordingAudioPathKey,
    );

    if (audioPath == null || audioPath.isEmpty) {
      _sendEvent(
        event: foregroundRecordingFailedEvent,
        error: 'Missing foreground recording audio path.',
      );
      return;
    }

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 48000,
          numChannels: 1,
        ),
        path: audioPath,
      );

      _audioPath = audioPath;
      _isRecording = true;

      _sendEvent(event: foregroundRecordingStartedEvent, audioPath: audioPath);
    } catch (error) {
      _sendEvent(
        event: foregroundRecordingFailedEvent,
        audioPath: audioPath,
        error: error.toString(),
      );
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onReceiveData(Object data) {
    if (data == foregroundRecordingStopCommand) {
      unawaited(_stopAndReport());
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _stopAndReport();
    await _recorder.dispose();
  }

  Future<void> _stopAndReport() {
    if (!_isRecording) {
      return Future.value();
    }

    return _stopFuture ??= _performStopAndReport();
  }

  Future<void> _performStopAndReport() async {
    try {
      final stoppedPath = await _recorder.stop();
      final audioPath = stoppedPath ?? _audioPath;

      _isRecording = false;

      _sendEvent(event: foregroundRecordingStoppedEvent, audioPath: audioPath);
    } catch (error) {
      _sendEvent(
        event: foregroundRecordingFailedEvent,
        audioPath: _audioPath,
        error: error.toString(),
      );
    }
  }

  void _sendEvent({required String event, String? audioPath, String? error}) {
    FlutterForegroundTask.sendDataToMain({
      'type': foregroundRecordingMessageType,
      'event': event,
      'audioPath': ?audioPath,
      'error': ?error,
    });
  }
}

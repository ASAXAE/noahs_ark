import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart';

const foregroundRecordingAudioPathKey = 'foreground_recording_audio_path';
const foregroundRecordingStopCommand = 'foreground_recording_stop';
const foregroundRecordingStopButtonId = 'foreground_recording_stop_button';

const foregroundRecordingMessageType = 'foreground_recording';
const foregroundRecordingStartedEvent = 'started';
const foregroundRecordingStoppedEvent = 'stopped';
const foregroundRecordingFailedEvent = 'failed';

const foregroundRecordingAudioLevelEvent = 'audio_level';
const foregroundRecordingAudioLevelDbfsKey = 'audioLevelDbfs';

@pragma('vm:entry-point')
void startForegroundRecordingCallback() {
  FlutterForegroundTask.setTaskHandler(ForegroundRecordingTaskHandler());
}

class ForegroundRecordingTaskHandler extends TaskHandler {
  static const Duration _audioLevelInterval = Duration(milliseconds: 100);

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _audioLevelSubscription;

  bool _isRecording = false;
  bool _isStopping = false;
  String? _audioPath;
  DateTime? _startedAt;
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
      await FlutterForegroundTask.stopService();
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

      _startedAt = DateTime.now();

      _startAudioLevelReporting();

      _sendEvent(event: foregroundRecordingStartedEvent, audioPath: audioPath);
      _updateRecordingNotification(_startedAt!);
    } catch (error) {
      await _cancelAudioLevelReporting();
      _sendEvent(
        event: foregroundRecordingFailedEvent,
        audioPath: audioPath,
        error: error.toString(),
      );
      await FlutterForegroundTask.stopService();
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (!_isRecording || _isStopping) {
      return;
    }

    _updateRecordingNotification(timestamp);
  }

  void _updateRecordingNotification(DateTime now) {
    final startedAt = _startedAt;

    if (!_isRecording || startedAt == null) {
      return;
    }

    final elapsed = now.difference(startedAt);

    unawaited(
      FlutterForegroundTask.updateService(
        notificationTitle: '诺亚方舟正在录音',
        notificationText: '已录制 ${_formatElapsed(elapsed)}',
        notificationButtons: const [
          NotificationButton(
            id: foregroundRecordingStopButtonId,
            text: '停止并保存',
          ),
        ],
      ),
    );
  }

  String _formatElapsed(Duration duration) {
    final totalSeconds = duration.isNegative ? 0 : duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${twoDigits(hours)}:'
        '${twoDigits(minutes)}:'
        '${twoDigits(seconds)}';
  }

  @override
  void onReceiveData(Object data) {
    if (data == foregroundRecordingStopCommand) {
      unawaited(_stopAndReport());
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id != foregroundRecordingStopButtonId || !_isRecording || _isStopping) {
      return;
    }

    unawaited(_stopAndReport());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    try {
      await _stopAndReport();
    } finally {
      await _cancelAudioLevelReporting();
      await _recorder.dispose();
    }
  }

  Future<void> _stopAndReport() {
    if (!_isRecording) {
      return Future.value();
    }

    return _stopFuture ??= _performStopAndReport();
  }

  Future<void> _performStopAndReport() async {
    _isStopping = true;
    await _cancelAudioLevelReporting();

    unawaited(
      FlutterForegroundTask.updateService(
        notificationText: '正在停止并保存录音',
        notificationButtons: const [],
      ),
    );

    try {
      final stoppedPath = await _recorder.stop();
      final audioPath = stoppedPath ?? _audioPath;

      _isRecording = false;
      _startedAt = null;

      _sendEvent(event: foregroundRecordingStoppedEvent, audioPath: audioPath);
    } catch (error) {
      _sendEvent(
        event: foregroundRecordingFailedEvent,
        audioPath: _audioPath,
        error: error.toString(),
      );
    } finally {
      _isStopping = false;
      _stopFuture = null;
    }
  }

  void _startAudioLevelReporting() {
    if (_audioLevelSubscription != null) {
      return;
    }

    try {
      _audioLevelSubscription = _recorder
          .onAmplitudeChanged(_audioLevelInterval)
          .listen(
            (amplitude) {
              final audioLevelDbfs = amplitude.current;

              if (!_isRecording || _isStopping || !audioLevelDbfs.isFinite) {
                return;
              }

              _sendEvent(
                event: foregroundRecordingAudioLevelEvent,
                audioPath: _audioPath,
                audioLevelDbfs: audioLevelDbfs,
              );
            },
            onError: (Object _) {
              // 音量反馈失败不能中断录音。
            },
          );
    } catch (_) {
      // 不支持音量反馈时，录音仍然继续。
    }
  }

  Future<void> _cancelAudioLevelReporting() async {
    final subscription = _audioLevelSubscription;
    _audioLevelSubscription = null;

    if (subscription == null) {
      return;
    }

    try {
      await subscription.cancel();
    } catch (_) {
      // 不覆盖真正的录音停止结果。
    }
  }

  void _sendEvent({
    required String event,
    String? audioPath,
    String? error,
    double? audioLevelDbfs,
  }) {
    FlutterForegroundTask.sendDataToMain({
      'type': foregroundRecordingMessageType,
      'event': event,
      'audioPath': ?audioPath,
      'error': ?error,
      foregroundRecordingAudioLevelDbfsKey: ?audioLevelDbfs,
    });
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'audio_recorder_service.dart';
import 'foreground_recording_task_handler.dart';

class ForegroundAudioRecorderService implements CaptureAudioRecorder {
  ForegroundAudioRecorderService() {
    if (Platform.isAndroid) {
      FlutterForegroundTask.addTaskDataCallback(_taskDataCallback);
    }
  }

  static const int _serviceId = 5701;
  static const Duration _responseTimeout = Duration(seconds: 10);

  static void initialize() {
    if (!Platform.isAndroid) {
      return;
    }

    FlutterForegroundTask.initCommunicationPort();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'capture_recording',
        channelName: '闪念录音',
        channelDescription: '录制闪念时显示，提醒麦克风正在使用',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
        allowAutoRestart: false,
        stopWithTask: false,
      ),
    );
  }

  final AudioRecorderService _fallbackRecorder = AudioRecorderService();

  late final void Function(Object) _taskDataCallback = _onReceiveTaskData;

  Completer<String>? _startCompleter;
  Completer<String?>? _stopCompleter;
  String? _activeAudioPath;
  bool _disposed = false;

  @override
  Future<bool> requestPermission() async {
    _ensureNotDisposed();

    final microphoneGranted = await _fallbackRecorder.requestPermission();

    if (!microphoneGranted || !Platform.isAndroid) {
      return microphoneGranted;
    }

    var notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();

    if (notificationPermission != NotificationPermission.granted) {
      notificationPermission =
          await FlutterForegroundTask.requestNotificationPermission();
    }

    return notificationPermission == NotificationPermission.granted;
  }

  @override
  Future<String> startRecordingAfterPermissionGranted() async {
    _ensureNotDisposed();

    if (!Platform.isAndroid) {
      return _fallbackRecorder.startRecordingAfterPermissionGranted();
    }

    if (_activeAudioPath != null ||
        _startCompleter != null ||
        await FlutterForegroundTask.isRunningService) {
      throw StateError('A foreground recording is already active.');
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final audioDirectory = Directory(
      path.join(documentsDirectory.path, 'capture_audio'),
    );

    await audioDirectory.create(recursive: true);

    final fileName = 'capture_${DateTime.now().microsecondsSinceEpoch}.wav';
    final filePath = path.join(audioDirectory.path, fileName);

    final pathSaved = await FlutterForegroundTask.saveData(
      key: foregroundRecordingAudioPathKey,
      value: filePath,
    );

    if (!pathSaved) {
      throw StateError('Unable to prepare the foreground recording path.');
    }

    final startCompleter = Completer<String>();
    _startCompleter = startCompleter;
    _activeAudioPath = filePath;

    try {
      final result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: const [ForegroundServiceTypes.microphone],
        notificationTitle: '诺亚方舟正在录音',
        notificationText: '闪念录音进行中，点击返回应用',
        callback: startForegroundRecordingCallback,
      );

      if (result is ServiceRequestFailure) {
        throw result.error;
      }

      return await startCompleter.future.timeout(_responseTimeout);
    } catch (_) {
      await _stopForegroundServiceIfRunning();
      _activeAudioPath = null;
      await FlutterForegroundTask.removeData(
        key: foregroundRecordingAudioPathKey,
      );
      rethrow;
    } finally {
      _startCompleter = null;
    }
  }

  @override
  Future<String?> stopRecording() async {
    _ensureNotDisposed();

    if (!Platform.isAndroid) {
      return _fallbackRecorder.stopRecording();
    }

    if (_activeAudioPath == null ||
        !await FlutterForegroundTask.isRunningService) {
      return null;
    }

    final stopCompleter = Completer<String?>();
    _stopCompleter = stopCompleter;

    FlutterForegroundTask.sendDataToTask(foregroundRecordingStopCommand);

    try {
      final stoppedPath = await stopCompleter.future.timeout(_responseTimeout);

      final result = await FlutterForegroundTask.stopService();

      if (result is ServiceRequestFailure) {
        throw result.error;
      }

      return stoppedPath;
    } finally {
      await _stopForegroundServiceIfRunning();
      _stopCompleter = null;
      _activeAudioPath = null;
      await FlutterForegroundTask.removeData(
        key: foregroundRecordingAudioPathKey,
      );
    }
  }

  void _onReceiveTaskData(Object data) {
    if (data is! Map || data['type'] != foregroundRecordingMessageType) {
      return;
    }

    final event = data['event'];
    final audioPath = data['audioPath'];

    if (event == foregroundRecordingStartedEvent) {
      final completer = _startCompleter;

      if (completer == null || completer.isCompleted) {
        return;
      }

      if (audioPath is String) {
        completer.complete(audioPath);
      } else {
        completer.completeError(
          StateError('Foreground recorder returned no audio path.'),
        );
      }

      return;
    }

    if (event == foregroundRecordingStoppedEvent) {
      final completer = _stopCompleter;

      if (completer != null && !completer.isCompleted) {
        completer.complete(audioPath is String ? audioPath : _activeAudioPath);
      }

      return;
    }

    if (event == foregroundRecordingFailedEvent) {
      final error = StateError(
        data['error']?.toString() ?? 'Foreground recording failed.',
      );

      final startCompleter = _startCompleter;

      if (startCompleter != null && !startCompleter.isCompleted) {
        startCompleter.completeError(error);
        return;
      }

      final stopCompleter = _stopCompleter;

      if (stopCompleter != null && !stopCompleter.isCompleted) {
        stopCompleter.completeError(error);
      }
    }
  }

  Future<void> _stopForegroundServiceIfRunning() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {
      // Preserve the original recording error during cleanup.
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('ForegroundAudioRecorderService is disposed.');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    if (Platform.isAndroid) {
      await _stopForegroundServiceIfRunning();
      FlutterForegroundTask.removeTaskDataCallback(_taskDataCallback);
    }

    await _fallbackRecorder.dispose();
  }
}

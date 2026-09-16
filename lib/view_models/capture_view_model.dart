import 'dart:async';
import 'dart:collection';

import '../models/capture_recording_state.dart';
import '../repositories/capture_repository.dart';
import '../models/capture_playback_state.dart';

import 'package:flutter/foundation.dart';

typedef CaptureTranscriptionRunner = Future<void> Function(int draftId);

class CaptureViewModel extends ChangeNotifier {
  CaptureViewModel({
    required CaptureRepository repository,
    required CaptureTranscriptionRunner runTranscription,
    this.onQueueDrained,
  }) : _repository = repository,
       _runTranscription = runTranscription {
    _repository.recordingState.addListener(_handleRecordingStateChanged);
    _repository.playbackState.addListener(_handlePlaybackStateChanged);
    _syncAudioLevelSubscription();
  }

  final VoidCallback? onQueueDrained;
  final CaptureTranscriptionRunner _runTranscription;
  final List<int> _queuedDraftIds = [];
  final CaptureRepository _repository;

  Future<void>? _drainFuture;
  int? _activeDraftId;
  bool _disposed = false;
  StreamSubscription<double>? _audioLevelSubscription;
  double _recordingAudioLevel = 0;

  UnmodifiableListView<int> get queuedDraftIds =>
      UnmodifiableListView(_queuedDraftIds);

  CaptureRecordingState get recordingState => _repository.currentRecordingState;

  CapturePlaybackState get playbackState => _repository.currentPlaybackState;

  bool get isRecording => recordingState.isRecording;

  bool get isRecordingActionInProgress => recordingState.isActionInProgress;

  double get recordingAudioLevel => _recordingAudioLevel;

  Future<bool> startRecording() {
    return _repository.startRecording();
  }

  Future<int?> stopAndSaveRecording() {
    return _repository.stopAndSaveRecording();
  }

  Future<bool> togglePlayback(String audioPath) {
    return _repository.togglePlayback(audioPath);
  }

  Future<void> seekPlayback(Duration position) {
    return _repository.seekPlayback(position);
  }

  Future<void> stopPlayback({String? audioPath}) {
    return _repository.stopPlayback(audioPath: audioPath);
  }

  void _handleRecordingStateChanged() {
    _syncAudioLevelSubscription();
    _notifyListeners();
  }

  void _handlePlaybackStateChanged() {
    _notifyListeners();
  }

  void _syncAudioLevelSubscription() {
    if (!recordingState.isRecording) {
      _cancelAudioLevelSubscription();
      _recordingAudioLevel = 0;
      return;
    }

    if (_audioLevelSubscription != null) {
      return;
    }

    try {
      _audioLevelSubscription = _repository.audioLevelDbfs.listen(
        _handleAudioLevelDbfs,
        onError: (Object _) {},
      );
    } catch (_) {
      // 音量显示是辅助功能，不能让它导致录音启动失败。
    }
  }

  void _handleAudioLevelDbfs(double dbfs) {
    if (_disposed || !recordingState.isRecording || !dbfs.isFinite) {
      return;
    }

    final level = ((dbfs + 60.0) / 60.0).clamp(0.0, 1.0).toDouble();

    if (level == _recordingAudioLevel) {
      return;
    }

    _recordingAudioLevel = level;
    _notifyListeners();
  }

  void _cancelAudioLevelSubscription() {
    final subscription = _audioLevelSubscription;
    _audioLevelSubscription = null;

    if (subscription != null) {
      unawaited(_cancelAudioLevelSubscriptionQuietly(subscription));
    }
  }

  Future<void> _cancelAudioLevelSubscriptionQuietly(
    StreamSubscription<double> subscription,
  ) async {
    try {
      await subscription.cancel();
    } catch (_) {
      // 取消音量监听失败也不影响录音状态切换。
    }
  }

  int? get activeDraftId => _activeDraftId;

  bool get isProcessing => _activeDraftId != null;

  bool isQueued(int draftId) {
    return _queuedDraftIds.contains(draftId);
  }

  int? queuePositionFor(int draftId) {
    final index = _queuedDraftIds.indexOf(draftId);

    if (index == -1) {
      return null;
    }

    return index + 1;
  }

  bool submitDraft(int draftId) {
    if (_disposed ||
        draftId <= 0 ||
        _activeDraftId == draftId ||
        isQueued(draftId)) {
      return false;
    }

    _queuedDraftIds.add(draftId);
    _notifyListeners();
    _drainFuture ??= _drainQueue();
    return true;
  }

  bool cancelQueuedDraft(int draftId) {
    if (_disposed) {
      return false;
    }

    final removed = _queuedDraftIds.remove(draftId);

    if (removed) {
      _notifyListeners();
    }

    return removed;
  }

  Future<void> waitUntilIdle() async {
    while (true) {
      final drainFuture = _drainFuture;

      if (drainFuture == null) {
        return;
      }

      await drainFuture;
    }
  }

  Future<void> _drainQueue() async {
    var processedAnyDraft = false;

    try {
      while (!_disposed && _queuedDraftIds.isNotEmpty) {
        final draftId = _queuedDraftIds.removeAt(0);
        processedAnyDraft = true;
        _activeDraftId = draftId;
        _notifyListeners();

        try {
          await _runTranscription(draftId);
        } catch (error, stackTrace) {
          debugPrint('转写队列任务 $draftId 失败：$error');
          debugPrintStack(stackTrace: stackTrace);
        } finally {
          if (_activeDraftId == draftId) {
            _activeDraftId = null;
          }

          _notifyListeners();
        }
      }
    } finally {
      _drainFuture = null;

      if (!_disposed && processedAnyDraft) {
        onQueueDrained?.call();
      }
    }
  }

  void _notifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _repository.recordingState.removeListener(_handleRecordingStateChanged);
    _repository.playbackState.removeListener(_handlePlaybackStateChanged);
    _disposed = true;
    _cancelAudioLevelSubscription();
    _recordingAudioLevel = 0;
    _queuedDraftIds.clear();
    super.dispose();
  }
}

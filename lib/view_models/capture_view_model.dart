import 'dart:collection';

import 'package:flutter/foundation.dart';

typedef CaptureTranscriptionRunner = Future<void> Function(int draftId);

class CaptureViewModel extends ChangeNotifier {
  CaptureViewModel({
    required CaptureTranscriptionRunner runTranscription,
    this.onQueueDrained,
  }) : _runTranscription = runTranscription;

  final VoidCallback? onQueueDrained;
  final CaptureTranscriptionRunner _runTranscription;
  final List<int> _queuedDraftIds = [];

  Future<void>? _drainFuture;
  int? _activeDraftId;
  bool _disposed = false;

  UnmodifiableListView<int> get queuedDraftIds =>
      UnmodifiableListView(_queuedDraftIds);

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
    _disposed = true;
    _queuedDraftIds.clear();
    super.dispose();
  }
}

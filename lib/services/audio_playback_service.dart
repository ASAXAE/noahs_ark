import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

abstract interface class CaptureAudioPlayback {
  Future<bool> play(String filePath);

  Future<void> pause();

  Future<void> resume();

  Stream<Duration> get onPositionChanged;

  Stream<Duration> get onDurationChanged;

  Future<void> seek(Duration position);

  Stream<void> get onPlayerComplete;

  Future<void> stop();

  Future<void> dispose();
}

class AudioPlaybackService implements CaptureAudioPlayback {
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final _durations = StreamController<Duration>.broadcast(sync: true);
  final _completions = StreamController<void>.broadcast(sync: true);

  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<void>? _completionSubscription;
  int _generation = 0;
  bool _disposed = false;

  @override
  Stream<Duration> get onPositionChanged => _positions.stream;

  @override
  Stream<Duration> get onDurationChanged => _durations.stream;

  @override
  Stream<void> get onPlayerComplete => _completions.stream;

  @override
  Future<bool> play(String filePath) async {
    if (_disposed) return false;

    final generation = ++_generation;
    await _retirePlayer();

    if (_disposed || generation != _generation) return false;
    if (!await File(filePath).exists()) return false;
    if (_disposed || generation != _generation) return false;

    final player = AudioPlayer();
    _player = player;

    _positionSubscription = player.onPositionChanged.listen((position) {
      if (!_disposed && identical(_player, player)) {
        _positions.add(position);
      }
    });
    _durationSubscription = player.onDurationChanged.listen((duration) {
      if (!_disposed && identical(_player, player)) {
        _durations.add(duration);
      }
    });
    _completionSubscription = player.onPlayerComplete.listen((_) {
      if (!_disposed && identical(_player, player)) {
        _completions.add(null);
      }
    });

    try {
      await player.play(DeviceFileSource(filePath));
      return !_disposed &&
          generation == _generation &&
          identical(_player, player);
    } catch (_) {
      if (identical(_player, player)) {
        await _retirePlayer();
      }
      rethrow;
    }
  }

  @override
  Future<void> pause() => _player?.pause() ?? Future<void>.value();

  @override
  Future<void> resume() => _player?.resume() ?? Future<void>.value();

  @override
  Future<void> seek(Duration position) =>
      _player?.seek(position) ?? Future<void>.value();

  @override
  Future<void> stop() async {
    ++_generation;
    await _retirePlayer();
  }

  Future<void> _retirePlayer() async {
    final player = _player;
    _player = null;

    final positionSubscription = _positionSubscription;
    final durationSubscription = _durationSubscription;
    final completionSubscription = _completionSubscription;
    _positionSubscription = null;
    _durationSubscription = null;
    _completionSubscription = null;

    try {
      await Future.wait<void>([
        if (positionSubscription != null) positionSubscription.cancel(),
        if (durationSubscription != null) durationSubscription.cancel(),
        if (completionSubscription != null) completionSubscription.cancel(),
      ]);
    } finally {
      if (player != null) {
        await player.dispose();
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    await _retirePlayer();
    await _positions.close();
    await _durations.close();
    await _completions.close();
  }
}

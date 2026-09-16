import 'dart:async';

import 'package:flutter/material.dart';

class CapturePlaybackProgress extends StatefulWidget {
  const CapturePlaybackProgress({
    super.key,
    required this.position,
    required this.duration,
    required this.isLoading,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final bool isLoading;
  final Future<void> Function(Duration position) onSeek;

  @override
  State<CapturePlaybackProgress> createState() =>
      _CapturePlaybackProgressState();
}

class _CapturePlaybackProgressState extends State<CapturePlaybackProgress> {
  double? _dragProgress;
  bool _seekInProgress = false;

  @override
  Widget build(BuildContext context) {
    final safeDuration = widget.duration.isNegative
        ? Duration.zero
        : widget.duration;
    final safePosition = _clampPosition(widget.position, safeDuration);
    final durationMilliseconds = safeDuration.inMilliseconds;

    final actualProgress = durationMilliseconds <= 0
        ? 0.0
        : (safePosition.inMilliseconds / durationMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble();

    final shownProgress = (_dragProgress ?? actualProgress)
        .clamp(0.0, 1.0)
        .toDouble();

    final shownPosition = _dragProgress == null
        ? safePosition
        : Duration(
            milliseconds: (durationMilliseconds * shownProgress).round(),
          );

    final canSeek =
        !widget.isLoading && !_seekInProgress && durationMilliseconds > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Slider(
          value: shownProgress,
          label: _formatDuration(shownPosition),
          onChanged: canSeek
              ? (value) {
                  setState(() => _dragProgress = value);
                }
              : null,
          onChangeEnd: canSeek
              ? (value) {
                  unawaited(_commitSeek(value));
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                _formatDuration(shownPosition),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              Text(
                _formatDuration(safeDuration),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _commitSeek(double progress) async {
    final durationMilliseconds = widget.duration.inMilliseconds;

    if (_seekInProgress || durationMilliseconds <= 0) {
      return;
    }

    final target = Duration(
      milliseconds: (durationMilliseconds * progress).round(),
    );

    setState(() {
      _dragProgress = progress;
      _seekInProgress = true;
    });

    try {
      await widget.onSeek(target);
    } catch (error) {
      debugPrint('调整播放位置失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _dragProgress = null;
          _seekInProgress = false;
        });
      }
    }
  }

  Duration _clampPosition(Duration position, Duration duration) {
    if (position.isNegative) {
      return Duration.zero;
    }

    if (duration.inMilliseconds > 0 &&
        position.inMilliseconds > duration.inMilliseconds) {
      return duration;
    }

    return position;
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.isNegative ? 0 : duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    if (hours > 0) {
      return '${twoDigits(hours)}:'
          '${twoDigits(minutes)}:'
          '${twoDigits(seconds)}';
    }

    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}

import 'package:flutter/material.dart';

import '../../models/capture_recording_state.dart';

class CaptureRecordingPanel extends StatelessWidget {
  const CaptureRecordingPanel({
    super.key,
    required this.state,
    required this.recordingAudioLevel,
    required this.elapsed,
    required this.onPressed,
  });

  final CaptureRecordingState state;
  final double recordingAudioLevel;
  final Duration elapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final seconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
    final elapsedText =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('录制闪念', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              '录音保存在本机，不会由应用上传。开始后可在后台继续录制，'
              '请点击“停止并保存”结束。转写需要另行选择。',
            ),
            if (state.hasActiveRecording) ...[
              const SizedBox(height: 12),
              Text('已录制 $elapsedText'),
              const SizedBox(height: 8),
              const Text('实时音量'),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: recordingAudioLevel, minHeight: 6),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: state.isActionInProgress ? null : onPressed,
              icon: Icon(
                state.isRecording
                    ? Icons.stop_circle_outlined
                    : Icons.mic_none_outlined,
              ),
              label: Text(
                state.isActionInProgress
                    ? '处理中…'
                    : state.isRecording
                    ? '停止并保存'
                    : '开始录音',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

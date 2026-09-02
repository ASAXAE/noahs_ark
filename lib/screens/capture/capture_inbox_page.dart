import 'package:flutter/material.dart';

import '../../database/ark_database.dart';
import '../../models/capture_draft.dart';
import '../../services/audio_playback_service.dart';
import '../../services/audio_recorder_service.dart';

class CaptureInboxPage extends StatefulWidget {
  const CaptureInboxPage({super.key, required this.onRetryTranscription});

  final Future<void> Function(int draftId) onRetryTranscription;

  @override
  State<CaptureInboxPage> createState() => _CaptureInboxPageState();
}

class _CaptureInboxPageState extends State<CaptureInboxPage> {
  final _audioPlaybackService = AudioPlaybackService();
  final _audioRecorderService = AudioRecorderService();
  String? _deletingAudioPath;
  int? _retryingDraftId;
  List<CaptureDraft> _drafts = [];
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  @override
  void dispose() {
    _audioPlaybackService.dispose();
    _audioRecorderService.dispose();
    super.dispose();
  }

  Future<void> _playDraft(CaptureDraft draft) async {
    try {
      final started = await _audioPlaybackService.play(draft.audioPath);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(started ? '正在播放原始录音' : '找不到原始录音文件')),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('播放失败 ，请重试')));
    }
  }

  Future<void> _retryDraft(CaptureDraft draft) async {
    final draftId = draft.id;

    if (draftId == null || _retryingDraftId != null) return;

    setState(() => _retryingDraftId = draftId);

    try {
      await widget.onRetryTranscription(draftId);

      if (!mounted) return;
      await _loadDrafts();
    } finally {
      if (mounted) {
        setState(() => _retryingDraftId = null);
      }
    }
  }

  Future<void> _deleteDraft(CaptureDraft draft) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('删除这条闪念？'),
              content: const Text('原始录音和闪念草稿都会从本机永久删除。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('删除'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() => _deletingAudioPath = draft.audioPath);

    try {
      await _audioPlaybackService.stop();

      final audioDeleted = await _audioRecorderService.deleteRecording(
        draft.audioPath,
      );

      if (!audioDeleted) {
        if (!mounted) return;

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有找到可安全删除的原始录音，草稿已保留')));
        return;
      }

      await ArkDatabase.instance.deleteCaptureDraftByAudioPath(draft.audioPath);

      if (!mounted) return;

      await _loadDrafts();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('闪念和原始录音已删除')));
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
    } finally {
      if (mounted) {
        setState(() => _deletingAudioPath = null);
      }
    }
  }

  Future<void> _loadDrafts() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });

    try {
      final drafts = await ArkDatabase.instance.getCaptureDrafts();

      if (!mounted) return;

      setState(() {
        _drafts = drafts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('闪念收集箱')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('读取闪念失败'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadDrafts, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_drafts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_none_outlined, size: 48),
            SizedBox(height: 12),
            Text('还没有等待整理的闪念'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDrafts,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _drafts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _buildDraftCard(_drafts[index]);
        },
      ),
    );
  }

  Widget _buildDraftCard(CaptureDraft draft) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_statusIcon(draft.transcriptionStatus)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusLabel(draft.transcriptionStatus),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  _formatDate(draft.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_draftDescription(draft)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _playDraft(draft),
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('播放原音'),
                ),
                if (draft.transcriptionStatus ==
                    CaptureTranscriptionStatus.failed)
                  FilledButton.icon(
                    onPressed: _retryingDraftId == null
                        ? () => _retryDraft(draft)
                        : null,
                    icon: _retryingDraftId == draft.id
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_outlined),
                    label: Text(_retryingDraftId == draft.id ? '重试中' : '重新转写'),
                  ),

                TextButton.icon(
                  onPressed: _deletingAudioPath == null
                      ? () => _deleteDraft(draft)
                      : null,
                  icon: _deletingAudioPath == draft.audioPath
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(
                    _deletingAudioPath == draft.audioPath ? '删除中' : '删除',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _draftDescription(CaptureDraft draft) {
    switch (draft.transcriptionStatus) {
      case CaptureTranscriptionStatus.pending:
        return '原始录音已保存，等待转写';
      case CaptureTranscriptionStatus.transcribing:
        return '正在本地转写';
      case CaptureTranscriptionStatus.completed:
        final transcript = draft.transcript?.trim();
        return transcript == null || transcript.isEmpty
            ? '转写完成，但没有识别到文字'
            : transcript;
      case CaptureTranscriptionStatus.failed:
        return '转写失败，可以稍后重试';
    }
  }

  String _statusLabel(CaptureTranscriptionStatus status) {
    switch (status) {
      case CaptureTranscriptionStatus.pending:
        return '等待转写';
      case CaptureTranscriptionStatus.transcribing:
        return '转写中';
      case CaptureTranscriptionStatus.completed:
        return '等待整理';
      case CaptureTranscriptionStatus.failed:
        return '转写失败';
    }
  }

  IconData _statusIcon(CaptureTranscriptionStatus status) {
    switch (status) {
      case CaptureTranscriptionStatus.pending:
        return Icons.schedule_outlined;
      case CaptureTranscriptionStatus.transcribing:
        return Icons.graphic_eq_outlined;
      case CaptureTranscriptionStatus.completed:
        return Icons.check_circle_outline;
      case CaptureTranscriptionStatus.failed:
        return Icons.error_outline;
    }
  }

  String _formatDate(DateTime data) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${data.year}/${twoDigits(data.month)}/${twoDigits(data.day)}  '
        '${twoDigits(data.hour)}:${twoDigits(data.minute)}';
  }
}

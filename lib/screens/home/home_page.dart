import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../database/ark_database.dart';
import '../../models/thought.dart';
import '../thinking/thinking_page.dart';
import '../detail/thought_detail_page.dart';
import '../../widgets/thought_card.dart';
import '../../services/api_service.dart';
import '../../services/backup_service.dart';
import '../settings/settings_page.dart';
import '../../models/auth_session.dart';
import '../../services/auth_session_storage.dart';
import '../../services/api_exception.dart';
import '../../services/audio_recorder_service.dart';
import '../../services/audio_playback_service.dart';
import '../../models/capture_draft.dart';
import '../../services/transcription_model_manager.dart';
import '../../services/sherpa_transcription_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  final _audioRecorderService = AudioRecorderService();
  final _audioPlaybackService = AudioPlaybackService();
  final _transcriptionModelManager = TranscriptionModelManager();
  bool _modelDownloadInProgress = false;
  final ValueNotifier<AuthSession?> _authSessionNotifier =
      ValueNotifier<AuthSession?>(null);

  SherpaTranscriptionService? _transcriptionService;
  bool _transcriptionInProgress = false;

  final Set<int> _expandedThoughtIds = {};
  List<Thought> _thoughts = [];
  bool _loading = true;
  bool _favoritesOnly = false;
  bool _hasSearchText = false;
  String? _selectedTag;
  bool _isRecording = false;
  bool _recordingActionInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadThoughts();
    _restoreAuthSession();
  }

  Future<int> _saveCaptureDraft(String audioPath) {
    final now = DateTime.now();

    final draft = CaptureDraft(
      audioPath: audioPath,
      createdAt: now,
      updatedAt: now,
    );

    return ArkDatabase.instance.insertCaptureDraft(draft);
  }

  Future<void> _prepareTranscriptionModel() async {
    if (_modelDownloadInProgress) {
      return;
    }

    if (await _transcriptionModelManager.isInstalled()) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('离线转写模型已经准备完成')),
      );
      return;
    }

    if (!mounted) return;

    final shouldDownload =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('下载离线转写模型？'),
              content: const Text(
                '模型约 228 MB，只保存在当前设备。'
                    '原始录音不会上传到服务器。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('下载'),
                ),
              ],
            );
          },
        ) ??
            false;

    if (!shouldDownload || !mounted) {
      return;
    }

    _modelDownloadInProgress = true;
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      const SnackBar(
        duration: Duration(days: 1),
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('正在下载离线转写模型，请保持应用开启')),
          ],
        ),
      ),
    );

    try {
      await _transcriptionModelManager.download();

      if (!mounted) return;

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('离线转写模型准备完成')),
      );
    } catch (error) {
      if (!mounted) return;

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('模型下载失败，请检查网络后重试')),
      );
    } finally {
      _modelDownloadInProgress = false;
    }
  }

  Future<TranscriptionModelFiles?> _getTranscriptionModelFiles() async {
    if (!await _transcriptionModelManager.isInstalled()) {
      await _prepareTranscriptionModel();
    }

    if (!await _transcriptionModelManager.isInstalled()) {
      return null;
    }

    return _transcriptionModelManager.getLocalFiles();
  }

  Future<void> _transcribeCaptureDraft(int draftId) async {
    if (_transcriptionInProgress) {
      return;
    }

    _transcriptionInProgress = true;
    CaptureDraft? transcribingDraft;

    try {
      final draft = await ArkDatabase.instance.getCaptureDraft(draftId);

      if (draft == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有找到对应的闪念草稿')),
          );
        }
        return;
      }

      final modelFiles = await _getTranscriptionModelFiles();
      if (modelFiles == null) {
        return;
      }

      transcribingDraft = draft.copyWith(
        transcriptionStatus: CaptureTranscriptionStatus.transcribing,
        clearTranscriptionError: true,
        updatedAt: DateTime.now(),
      );

      await ArkDatabase.instance.updateCaptureDraft(transcribingDraft);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(minutes: 2),
            content: Text('正在本地转写，原始录音会继续保留'),
          ),
        );
      }

      _transcriptionService ??= SherpaTranscriptionService(
        modelPath: modelFiles.modelPath,
        tokensPath: modelFiles.tokensPath,
      );

      final transcript = await _transcriptionService!.transcribeFile(
        draft.audioPath,
      );

      final completedDraft = transcribingDraft.copyWith(
        transcript: transcript,
        transcriptionStatus: CaptureTranscriptionStatus.completed,
        clearTranscriptionError: true,
        updatedAt: DateTime.now(),
      );

      await ArkDatabase.instance.updateCaptureDraft(completedDraft);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('转写完成'),
            content: SelectableText(transcript),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  unawaited(_playRecording(completedDraft.audioPath));
                },
                child: const Text('播放原音'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (transcribingDraft != null) {
        final failedDraft = transcribingDraft.copyWith(
          transcriptionStatus: CaptureTranscriptionStatus.failed,
          transcriptionError: error.toString(),
          updatedAt: DateTime.now(),
        );

        await ArkDatabase.instance.updateCaptureDraft(failedDraft);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('转写失败，原始录音仍然保留'),
            action: SnackBarAction(
              label: '重试',
              onPressed: () {
                unawaited(_transcribeCaptureDraft(draftId));
              },
            ),
          ),
        );
      }
    } finally {
      _transcriptionInProgress = false;
    }
  }

  Future<void> _toggleRecording() async {
    if (_recordingActionInProgress) {
      return;
    }

    setState(() => _recordingActionInProgress = true);

    try {
      if (_isRecording) {
        final recordingPath = await _audioRecorderService.stopRecording();

        final draftId = recordingPath == null
            ? null
            : await _saveCaptureDraft(recordingPath);

        if (!mounted) return;

        setState(() => _isRecording = false);

        if (recordingPath != null && draftId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Expanded(child: Text('原始录音已保存到本机')),
                  TextButton(
                    onPressed: () {
                      unawaited(_playRecording(recordingPath));
                    },
                    child: const Text('播放'),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: '转写',
                onPressed: () {
                  unawaited(_transcribeCaptureDraft(draftId));
                },
              ),
            ),
          );
        }

        return;
      }

      final recordingPath = await _audioRecorderService.startRecording();

      if (!mounted) return;

      if (recordingPath == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('需要麦克风权限才能录制闪念')));
        return;
      }

      setState(() => _isRecording = true);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('录音操作失败，请重试')));
    } finally {
      if (mounted) {
        setState(() => _recordingActionInProgress = false);
      }
    }
  }

  Future<void> _playRecording(String filePath) async {
    try {
      final didStartPlaying = await _audioPlaybackService.play(filePath);

      if (!mounted) return;

      if (!didStartPlaying) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('找不到录音文件')));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('正在播放原始录音'),
          action: SnackBarAction(
            label: '删除',
            onPressed: () {
              unawaited(_deleteRecording(filePath));
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('播放失败，请重试')));
    }
  }

  Future<void> _deleteRecording(String filePath) async {
    try {
      await _audioPlaybackService.stop();

      final deleted = await _audioRecorderService.deleteRecording(filePath);
      if (deleted) {
        await ArkDatabase.instance.deleteCaptureDraftByAudioPath(filePath);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(deleted ? '原始录音已从本机删除' : '没有找到可删除的录音')),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('删除录音失败，请重试')));
    }
  }

  Future<void> _restoreAuthSession() async {
    try {
      final accessToken = await AuthSessionStorage.instance.readAccessToken();

      if (accessToken == null || accessToken.isEmpty) {
        return;
      }

      final user = await ApiService().fetchCurrentUser(
        accessToken: accessToken,
      );

      if (!mounted) return;

      _authSessionNotifier.value = AuthSession(
        accessToken: accessToken,
        user: user,
      );
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await AuthSessionStorage.instance.deleteAccessToken();

        if (!mounted) return;
        _authSessionNotifier.value = null;
      }

      debugPrint('恢复登录状态失败：$error');
    } catch (error) {
      debugPrint('恢复登录状态失败：$error');
    }
  }

  Future<void> _loadThoughts() async {
    final thoughts = await ArkDatabase.instance.getThoughts(
      query: _searchController.text,
      tag: _selectedTag,
      favoritesOnly: _favoritesOnly,
    );
    if (!mounted) return;
    setState(() {
      _thoughts = thoughts;
      _loading = false;
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          authSessionNotifier: _authSessionNotifier,
          onExportBackup: _exportBackup,
          onRestoreBackup: _previewBackup,
        ),
      ),
    );

    await _loadThoughts();
  }

  Future<void> _openEditor([Thought? thought]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ThinkingPage(
          thought: thought,
          initialTag: thought == null ? _selectedTag : null,
        ),
      ),
    );
    if (changed == true) await _loadThoughts();
  }

  Future<void> _openDetail(Thought thought) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ThoughtDetailPage(thought: thought)),
    );

    if (changed == true) {
      await _loadThoughts();
    }
  }

  Future<void> _toggleFavorite(Thought thought) async {
    await ArkDatabase.instance.saveThought(
      thought.copyWith(isFavorite: !thought.isFavorite),
    );
    await _loadThoughts();
  }

  Future<void> _exportBackup() async {
    try {
      final thoughts = await ArkDatabase.instance.getThoughts();

      if (!mounted) {
        return;
      }

      if (thoughts.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('还没有可以导出的记录')));
        return;
      }

      await BackupService().exportThoughts(thoughts);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
    }
  }

  Future<void> _previewBackup() async {
    try {
      final backup = await BackupService().pickAndReadBackup();

      if (backup == null || !mounted) {
        return;
      }

      final localExportTime = backup.exportedAt.toLocal();
      final displayTime = localExportTime.toString().split('.').first;

      final shouldRestore = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('备份文件验证成功'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('记录数量：${backup.thoughts.length}'),
                const SizedBox(height: 8),
                Text('导出时间：$displayTime'),
                const SizedBox(height: 16),
                const Text('恢复不会删除现有记录，已经存在的相同记录会被跳过。'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: backup.thoughts.isEmpty
                    ? null
                    : () {
                        Navigator.pop(dialogContext, true);
                      },
                child: const Text('恢复记录'),
              ),
            ],
          );
        },
      );

      if (shouldRestore != true) {
        return;
      }

      final result = await ArkDatabase.instance.importThoughts(backup.thoughts);

      await _loadThoughts();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '恢复完成：新增 ${result.importedCount} 条，'
            '跳过 ${result.skippedCount} 条',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('备份验证失败：${error.message}')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('恢复备份失败：$error')));
    }
  }

  Future<void> _delete(Thought thought) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final title = thought.title.trim().isEmpty
            ? '无标题'
            : thought.title.trim();

        return AlertDialog(
          title: const Text('删除这条记录？'),
          content: Text('确定删除“$title”吗？删除后无法恢复。'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    final id = thought.id;

    if (confirmed != true || id == null) {
      return;
    }

    try {
      await ArkDatabase.instance.deleteThought(id);
      await _loadThoughts();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('记录已删除')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  Future<void> _testApiConnection() async {
    try {
      final serverThoughts = await ApiService().fetchThoughts();

      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                children: [
                  Text('服务器记录', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),

                  Expanded(
                    child: serverThoughts.isEmpty
                        ? const Center(child: Text('服务器还没有记录'))
                        : ListView.separated(
                            itemCount: serverThoughts.length,
                            separatorBuilder: (_, _) => const Divider(),
                            itemBuilder: (_, index) {
                              final thought = serverThoughts[index];

                              return ListTile(
                                title: Text(
                                  thought.title.isEmpty ? '无标题' : thought.title,
                                ),
                                subtitle: Text(thought.content),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(thought.tag),
                                    IconButton(
                                      tooltip: '编辑服务器记录',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () {
                                        _editServerThought(thought);
                                      },
                                    ),
                                    IconButton(
                                      tooltip: '删除服务器记录',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _deleteServerThought(thought);
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _createServerTestThought();
                      },
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('创建服务器测试记录'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('获取服务器记录失败：$error')));
    }
  }

  Future<void> _createServerTestThought() async {
    try {
      final createdThought = await ApiService().createTestThought();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('服务器记录创建成功：${createdThought.title}')),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建服务器记录失败：$error')));
    }
  }

  Future<void> _editServerThought(Thought thought) async {
    var editedTitle = thought.title;
    var editedContent = thought.content;
    var editedTag = thought.tag;
    String? validationMessage;

    final updatedThought = await showDialog<Thought>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('编辑服务器记录'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: thought.title,
                      onChanged: (value) {
                        editedTitle = value;
                      },
                      decoration: const InputDecoration(labelText: '标题'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: thought.content,
                      onChanged: (value) {
                        editedContent = value;
                      },
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: '正文',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: thought.tag,
                      onChanged: (value) {
                        editedTag = value;
                      },
                      decoration: const InputDecoration(labelText: '标签'),
                    ),
                    if (validationMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        validationMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    if (editedContent.trim().isEmpty ||
                        editedTag.trim().isEmpty) {
                      setDialogState(() {
                        validationMessage = '正文和标签不能为空';
                      });
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      thought.copyWith(
                        title: editedTitle.trim(),
                        content: editedContent.trim(),
                        tag: editedTag.trim(),
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updatedThought == null) {
      return;
    }

    try {
      final result = await ApiService().updateThought(updatedThought);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('服务器记录修改成功：${result.title}')));
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('修改服务器记录失败：$error')));
    }
  }

  Future<void> _deleteServerThought(Thought thought) async {
    final id = thought.id;

    if (id == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除服务器记录？'),
          content: Text(
            '确定删除“${thought.title.isEmpty ? '无标题' : thought.title}”吗？',
          ),
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
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ApiService().deleteThought(id);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('服务器记录已删除')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除服务器记录失败：$error')));
    }
  }

  bool get _hasActiveFilters {
    return _searchController.text.trim().isNotEmpty ||
        _selectedTag != null ||
        _favoritesOnly;
  }

  void _resetFilters() {
    _searchController.clear();

    setState(() {
      _hasSearchText = false;
      _selectedTag = null;
      _favoritesOnly = false;
    });

    _loadThoughts();
  }

  void _clearSearch() {
    _searchController.clear();

    setState(() {
      _hasSearchText = false;
    });

    _loadThoughts();
  }

  void _toggleThoughtExpanded(int id) {
    setState(() {
      if (_expandedThoughtIds.contains(id)) {
        _expandedThoughtIds.remove(id);
      } else {
        _expandedThoughtIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '诺亚方舟',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: _isRecording ? '停止录音' : '录制闪念',
            onPressed: _recordingActionInProgress ? null : _toggleRecording,
            icon: _recordingActionInProgress
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _isRecording
                        ? Icons.stop_circle_outlined
                        : Icons.mic_none_outlined,
                    color: _isRecording
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          if (kDebugMode)
            IconButton(
              tooltip: '测试后端连接',
              onPressed: _testApiConnection,
              icon: const Icon(Icons.cloud_outlined),
            ),
          IconButton(
            tooltip: _favoritesOnly ? '显示全部' : '只看收藏',
            onPressed: () {
              setState(() => _favoritesOnly = !_favoritesOnly);
              _loadThoughts();
            },
            icon: Icon(_favoritesOnly ? Icons.favorite : Icons.favorite_border),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('写下今天'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadThoughts,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                sliver: SliverList.list(
                  children: [_hero(), const SizedBox(height: 20), _filters()],
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_thoughts.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _emptyState())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList.separated(
                    itemCount: _thoughts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, index) {
                      final thought = _thoughts[index];
                      final id = thought.id;

                      return ThoughtCard(
                        thought: thought,
                        isExpanded:
                            id != null && _expandedThoughtIds.contains(id),
                        onTap: () => _openDetail(thought),
                        onToggleExpanded: () {
                          if (id != null) {
                            _toggleThoughtExpanded(id);
                          }
                        },
                        onEdit: () => _openEditor(thought),
                        onFavorite: () => _toggleFavorite(thought),
                        onDelete: () => _delete(thought),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: const Color(0xFF426B5A),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('今日思考', style: TextStyle(color: Colors.white70)),
              SizedBox(height: 6),
              Text(
                '把重要的想法留下来',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        CircleAvatar(
          radius: 28,
          backgroundColor: Colors.white.withValues(alpha: 0.15),
          child: const Icon(Icons.sailing, color: Colors.white, size: 30),
        ),
      ],
    ),
  );

  Widget _filters() => Column(
    children: [
      TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _hasSearchText = value.trim().isNotEmpty;
          });

          _loadThoughts();
        },
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: '搜索记录',
          suffixIcon: _hasSearchText
              ? IconButton(
                  tooltip: '清空搜索',
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.close),
                )
              : null,
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            ChoiceChip(
              label: const Text('全部'),
              selected: _selectedTag == null,
              onSelected: (_) {
                setState(() => _selectedTag = null);
                _loadThoughts();
              },
            ),
            for (final tag in Thought.tags) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(tag),
                selected: _selectedTag == tag,
                onSelected: (_) {
                  setState(() => _selectedTag = tag);
                  _loadThoughts();
                },
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _emptyState() {
    String title;
    String description;
    IconData icon;

    if (_searchController.text.trim().isNotEmpty) {
      title = '没有找到相关记录';
      description = '试试修改搜索内容';
      icon = Icons.search_off_outlined;
    } else if (_selectedTag != null) {
      title = '“$_selectedTag”标签还没有记录';
      description = '你可以写下一条属于这个标签的想法';
      icon = Icons.label_outline;
    } else if (_favoritesOnly) {
      title = '还没有收藏记录';
      description = '收藏重要的想法后，它们会出现在这里';
      icon = Icons.favorite_border;
    } else {
      title = '方舟还是空的';
      description = '写下此刻值得保存的想法';
      icon = Icons.auto_stories_outlined;
    }

    final hasActiveFilters = _hasActiveFilters;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: hasActiveFilters ? _resetFilters : _openEditor,
              icon: Icon(
                hasActiveFilters
                    ? Icons.filter_alt_off_outlined
                    : Icons.edit_outlined,
              ),
              label: Text(hasActiveFilters ? '查看全部记录' : '写下第一条记录'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_audioRecorderService.dispose());
    unawaited(_audioPlaybackService.dispose());
    _transcriptionService?.dispose();
    _transcriptionModelManager.dispose();
    _searchController.dispose();
    _authSessionNotifier.dispose();
    super.dispose();
  }
}

//Ctrl + Alt + L格式化 Ctrl + F当前文件搜索 Ctrl + Shift + F整个项目搜索 Ctrl + Shift + N 快速打开文件 Ctrl + F12查看当前文件结构
//fn + esc 转换f1-f12

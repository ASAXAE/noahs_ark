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
import '../capture/capture_inbox_page.dart';
import '../shell/app_shell.dart';
import 'widgets/home_hero.dart';
import 'widgets/home_filters.dart';
import 'widgets/home_empty_state.dart';
import '../debug/server_thoughts_debug_page.dart';

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
  int _captureInboxRefreshVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadThoughts();
    _restoreAuthSession();
  }

  Future<int> _saveCaptureDraft(String audioPath) async {
    final now = DateTime.now();

    final draft = CaptureDraft(
      audioPath: audioPath,
      createdAt: now,
      updatedAt: now,
    );

    final draftId = await ArkDatabase.instance.insertCaptureDraft(draft);

    if (mounted) {
      setState(() {
        _captureInboxRefreshVersion++;
      });
    }

    return draftId;
  }

  Future<void> _prepareTranscriptionModel() async {
    if (_modelDownloadInProgress) {
      return;
    }

    if (await _transcriptionModelManager.isInstalled()) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离线转写模型已经准备完成')));
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
      messenger.showSnackBar(const SnackBar(content: Text('离线转写模型准备完成')));
    } catch (error) {
      if (!mounted) return;

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('模型下载失败，请检查网络后重试')));
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('没有找到对应的闪念草稿')));
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

      if (mounted && transcribingDraft != null) {
        setState(() {
          _captureInboxRefreshVersion++;
        });
      }
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

  Future<void> _openServerThoughtsDebugPage() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ServerThoughtsDebugPage()),
    );
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

  Widget _buildArkPage(BuildContext context) {
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
          if (kDebugMode)
            IconButton(
              tooltip: '测试后端连接',
              onPressed: _openServerThoughtsDebugPage,
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
                  children: [
                    const HomeHero(),
                    const SizedBox(height: 20),
                    HomeFilters(
                      searchController: _searchController,
                      hasSearchText: _hasSearchText,
                      selectedTag: _selectedTag,
                      tags: Thought.tags,
                      onSearchChanged: (value) {
                        setState(() {
                          _hasSearchText = value.trim().isNotEmpty;
                        });

                        _loadThoughts();
                      },
                      onClearSearch: _clearSearch,
                      onTagSelected: (tag) {
                        setState(() {
                          _selectedTag = tag;
                        });

                        _loadThoughts();
                      },
                    ),
                  ],
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_thoughts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: HomeEmptyState(
                    searchText: _searchController.text,
                    selectedTag: _selectedTag,
                    favoritesOnly: _favoritesOnly,
                    onResetFilters: _resetFilters,
                    onCreateThought: _openEditor,
                  ),
                )
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

  @override
  Widget build(BuildContext context) {
    return AppShell(
      arkPage: _buildArkPage(context),
      capturePage: CaptureInboxPage(
        onRetryTranscription: _transcribeCaptureDraft,
        refreshVersion: _captureInboxRefreshVersion,
      ),
      profilePage: SettingsPage(
        authSessionNotifier: _authSessionNotifier,
        onExportBackup: _exportBackup,
        onRestoreBackup: _previewBackup,
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

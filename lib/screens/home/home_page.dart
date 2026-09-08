import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../database/ark_database.dart';
import '../../models/thought.dart';
import '../thinking/thinking_page.dart';
import '../detail/thought_detail_page.dart';
import '../../services/api_service.dart';
import '../settings/settings_page.dart';
import '../../models/auth_session.dart';
import '../../services/auth_session_storage.dart';
import '../../services/api_exception.dart';
import '../../services/transcription_model_manager.dart';
import '../../controllers/capture_controller.dart';
import '../capture/capture_inbox_page.dart';
import '../shell/app_shell.dart';
import 'widgets/home_hero.dart';
import 'widgets/home_filters.dart';
import 'widgets/home_empty_state.dart';
import 'widgets/home_thought_list.dart';
import '../debug/server_thoughts_debug_page.dart';
import '../../view_models/capture_view_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _captureController = CaptureController();
  late final CaptureViewModel _captureViewModel;
  bool _modelDownloadInProgress = false;
  final ValueNotifier<AuthSession?> _authSessionNotifier =
      ValueNotifier<AuthSession?>(null);

  final Set<int> _expandedThoughtIds = {};
  List<Thought> _thoughts = [];
  bool _loading = true;
  bool _favoritesOnly = false;
  bool _hasSearchText = false;
  String? _selectedTag;
  bool _isRecording = false;
  bool _recordingActionInProgress = false;
  bool _isAppInBackground = false;
  String? _pendingRecordingNotice;
  int _captureInboxRefreshVersion = 0;
  bool _queueCompletedDialogVisible = false;

  @override
  void initState() {
    super.initState();
    _captureViewModel = CaptureViewModel(
      runTranscription: _runQueuedTranscription,
      onQueueDrained: _showTranscriptionQueueCompletedDialog,
    );
    unawaited(_recoverInterruptedTranscriptions());
    WidgetsBinding.instance.addObserver(this);
    _loadThoughts();
    _restoreAuthSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('应用生命周期：${state.name}');

    if (state == AppLifecycleState.paused) {
      _isAppInBackground = true;
      unawaited(_stopRecordingForBackground());
    } else if (state == AppLifecycleState.resumed) {
      _isAppInBackground = false;
      _showPendingRecordingNotice();
    }
  }

  Future<void> _recoverInterruptedTranscriptions() async {
    try {
      final recoveredCount = await _captureController
          .recoverInterruptedTranscriptions();

      if (!mounted || recoveredCount == 0) {
        return;
      }

      setState(() {
        _captureInboxRefreshVersion++;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发现 $recoveredCount 条被中断的转写，可以在闪念收集箱中重试')),
        );
      });
    } catch (error) {
      debugPrint('恢复中断的转写状态失败：$error');
    }
  }

  Future<int> _saveCaptureDraft(String audioPath) async {
    final draftId = await _captureController.saveDraft(audioPath);

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

    if (await _captureController.isTranscriptionModelInstalled()) {
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
      await _captureController.downloadTranscriptionModel();

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
    if (!await _captureController.isTranscriptionModelInstalled()) {
      await _prepareTranscriptionModel();
    }

    if (!await _captureController.isTranscriptionModelInstalled()) {
      return null;
    }

    return _captureController.getTranscriptionModelFiles();
  }

  Future<void> _queueCaptureDraft(int draftId) {
    final submitted = _captureViewModel.submitDraft(draftId);

    if (!submitted && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该闪念正在转写或已经排队')));
    }

    return Future<void>.value();
  }

  void _showTranscriptionQueueCompletedDialog() {
    if (!mounted || _queueCompletedDialogVisible) {
      return;
    }

    _queueCompletedDialogVisible = true;

    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('转写队列已处理完毕'),
            content: const Text('所有排队任务都已处理，请在闪念收集箱中查看转写结果或失败状态。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('知道了'),
              ),
            ],
          );
        },
      ).whenComplete(() {
        _queueCompletedDialogVisible = false;
      }),
    );
  }

  Future<void> _runQueuedTranscription(int draftId) async {
    var transcriptionStarted = false;

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

      transcriptionStarted = true;

      await _captureController.transcribeDraft(
        draft: draft,
        modelFiles: modelFiles,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('转写失败，原始录音仍然保留'),
            action: SnackBarAction(
              label: '重试',
              onPressed: () {
                unawaited(_queueCaptureDraft(draftId));
              },
            ),
          ),
        );
      }

      rethrow;
    } finally {
      if (mounted && transcriptionStarted) {
        setState(() {
          _captureInboxRefreshVersion++;
        });
      }
    }
  }

  void _showPendingRecordingNotice() {
    if (!mounted ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final message = _pendingRecordingNotice;
    if (message == null) return;

    _pendingRecordingNotice = null;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _stopRecordingForBackground() async {
    if (!mounted ||
        !_isAppInBackground ||
        !_isRecording ||
        _recordingActionInProgress) {
      return;
    }

    setState(() => _recordingActionInProgress = true);

    try {
      final saved = await _stopRecordingAndSave();

      _pendingRecordingNotice = saved
          ? '应用进入后台，录音已自动停止并保存到闪念'
          : '录音已停止，但未获取到可保存的音频';
    } catch (error) {
      debugPrint('后台停止或保存录音失败：$error');
      _pendingRecordingNotice = '自动停止或保存失败，请检查录音状态和闪念列表';
    } finally {
      if (mounted) {
        setState(() => _recordingActionInProgress = false);
        _showPendingRecordingNotice();
      }
    }
  }

  Future<bool> _stopRecordingAndSave() async {
    final recordingPath = await _captureController.stopRecording();

    // 停止采集后立即更新状态，保存失败也不能继续显示录音中。
    if (mounted) {
      setState(() => _isRecording = false);
    }

    if (recordingPath == null) {
      return false;
    }

    await _saveCaptureDraft(recordingPath);
    return true;
  }

  Future<void> _toggleRecording() async {
    if (_recordingActionInProgress) {
      return;
    }

    setState(() => _recordingActionInProgress = true);

    try {
      if (_isRecording) {
        final saved = await _stopRecordingAndSave();

        if (!mounted) return;

        if (!saved) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('录音已停止，但未获取到可保存的音频')));
        }

        return;
      }

      final recordingPath = await _captureController.startRecording();

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

        if (_isAppInBackground && _isRecording) {
          unawaited(_stopRecordingForBackground());
        }
      }
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

  Future<void> _reloadThoughtsAndCaptureInbox() async {
    await _loadThoughts();

    if (!mounted) return;

    setState(() {
      _captureInboxRefreshVersion++;
    });
  }

  Future<void> _openDetail(Thought thought) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ThoughtDetailPage(thought: thought)),
    );

    if (changed == true) {
      await _reloadThoughtsAndCaptureInbox();
    }
  }

  Future<void> _toggleFavorite(Thought thought) async {
    await ArkDatabase.instance.saveThought(
      thought.copyWith(isFavorite: !thought.isFavorite),
    );
    await _loadThoughts();
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
      await _reloadThoughtsAndCaptureInbox();

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
                HomeThoughtList(
                  thoughts: _thoughts,
                  expandedThoughtIds: _expandedThoughtIds,
                  onOpen: _openDetail,
                  onToggleExpanded: _toggleThoughtExpanded,
                  onEdit: _openEditor,
                  onFavorite: _toggleFavorite,
                  onDelete: _delete,
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
        captureViewModel: _captureViewModel,
        onRetryTranscription: _queueCaptureDraft,
        onThoughtsChanged: _loadThoughts,
        refreshVersion: _captureInboxRefreshVersion,
      ),
      profilePage: SettingsPage(
        authSessionNotifier: _authSessionNotifier,
        onThoughtsChanged: _loadThoughts,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureViewModel.dispose();
    unawaited(_captureController.dispose());
    _searchController.dispose();
    _authSessionNotifier.dispose();
    super.dispose();
  }
}

//Ctrl + Alt + L格式化 Ctrl + F当前文件搜索 Ctrl + Shift + F整个项目搜索 Ctrl + Shift + N 快速打开文件 Ctrl + F12查看当前文件结构
//fn + esc 转换f1-f12

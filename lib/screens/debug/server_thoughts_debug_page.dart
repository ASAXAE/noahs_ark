import 'package:flutter/material.dart';

import '../../models/thought.dart';
import '../../services/api_service.dart';
import '../../services/api_exception.dart';

class ServerThoughtsDebugPage extends StatefulWidget {
  const ServerThoughtsDebugPage({super.key});

  @override
  State<ServerThoughtsDebugPage> createState() =>
      _ServerThoughtsDebugPageState();
}

class _ServerThoughtsDebugPageState extends State<ServerThoughtsDebugPage> {
  final _apiService = ApiService();

  List<Thought> _serverThoughts = [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _loginRequired = false;

  @override
  void initState() {
    super.initState();
    _loadServerThoughts();
  }

  Future<void> _loadServerThoughts() async {
    try {
      final thoughts = await _apiService.fetchThoughts();

      if (!mounted) return;

      setState(() {
        _serverThoughts = thoughts;
        _loading = false;
        _loadFailed = false;
        _loginRequired = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _loginRequired = error.isUnauthorized;
        _loadFailed = !error.isUnauthorized;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _loginRequired = false;
        _loadFailed = true;
      });
    }
  }

  void _retryLoading() {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _loginRequired = false;
    });

    _loadServerThoughts();
  }

  Future<void> _createServerTestThought() async {
    try {
      final createdThought = await _apiService.createTestThought();

      if (!mounted) return;

      setState(() {
        _serverThoughts = [createdThought, ..._serverThoughts];
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('服务器测试记录创建成功')));
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
      final result = await _apiService.updateThought(updatedThought);

      if (!mounted) return;

      setState(() {
        _serverThoughts = _serverThoughts.map((item) {
          return item.id == result.id ? result : item;
        }).toList();
      });

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
      await _apiService.deleteThought(id);

      if (!mounted) {
        return;
      }

      setState(() {
        _serverThoughts = _serverThoughts.where((item) {
          return item.id != id;
        }).toList();
      });

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器测试记录')),
      floatingActionButton: _loading || _loginRequired || _loadFailed
          ? null
          : FloatingActionButton.extended(
              onPressed: _createServerTestThought,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('创建测试记录'),
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loginRequired
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.login_outlined, size: 48),
                    SizedBox(height: 12),
                    Text('请先登录'),
                  ],
                ),
              )
            : _loadFailed
            ? Center(
                child: FilledButton(
                  onPressed: _retryLoading,
                  child: const Text('重新加载'),
                ),
              )
            : _serverThoughts.isEmpty
            ? const Center(child: Text('服务器还没有记录'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _serverThoughts.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  final thought = _serverThoughts[index];

                  return ListTile(
                    title: Text(thought.title.isEmpty ? '无标题' : thought.title),
                    subtitle: Text(thought.content),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(thought.tag),
                        IconButton(
                          tooltip: '编辑服务器记录',
                          onPressed: () => _editServerThought(thought),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: '删除服务器记录',
                          onPressed: () => _deleteServerThought(thought),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

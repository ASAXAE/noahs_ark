import 'package:flutter/material.dart';

import '../../models/thought.dart';
import '../thinking/thinking_page.dart';
import '../../database/ark_database.dart';

class ThoughtDetailPage extends StatelessWidget {
  const ThoughtDetailPage({super.key, required this.thought});

  final Thought thought;

  Future<void> _openEditor(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ThinkingPage(thought: thought)),
    );

    if (changed == true && context.mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _deleteThought(BuildContext context) async {
    final thoughtId = thought.id;

    if (thoughtId == null) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('删除这条记录？'),
              content: const Text(
                '正式记录会被删除；'
                '对应闪念和原始录音仍保留，可以重新整理。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  ),
                  child: const Text('删除'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !context.mounted) return;

    try {
      await ArkDatabase.instance.deleteThought(thoughtId);

      if (!context.mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记录详情'),
        actions: [
          IconButton(
            tooltip: '编辑',
            onPressed: () => _openEditor(context),
            icon: const Icon(Icons.edit_outlined),
          ),

          PopupMenuButton<String>(
            tooltip: '更多操作',
            padding: EdgeInsets.zero,
            color: Theme.of(context).cardColor,
            elevation: 10,
            offset: const Offset(-8, 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            onSelected: (value) {
              if (value == 'delete') {
                _deleteThought(context);
              }
            },
            itemBuilder: (menuContext) => [
              PopupMenuItem<String>(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      color: Theme.of(menuContext).colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '删除',
                      style: TextStyle(
                        color: Theme.of(menuContext).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                thought.title.isEmpty ? '无标题' : thought.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  Chip(
                    avatar: const Icon(Icons.sell_outlined, size: 18),
                    label: Text((thought.tag)),
                  ),

                  const Spacer(),

                  if (thought.isFavorite)
                    const Icon(Icons.favorite, color: Colors.redAccent),
                ],
              ),

              const SizedBox(height: 8),

              Text(
                thought.formattedDate,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),

              const Divider(height: 40),

              SelectableText(
                thought.content,
                style: const TextStyle(fontSize: 17, height: 1.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../database/ark_database.dart';
import '../../models/thought.dart';

class ThinkingPage extends StatefulWidget {
  const ThinkingPage({
    super.key,
    this.thought,
    this.initialTag,
    this.initialContent,
    this.onSave,
  });

  final Thought? thought;
  final String? initialTag;
  final String? initialContent;
  final Future<void> Function(Thought thought)? onSave;

  @override
  State<ThinkingPage> createState() => _ThinkingPageState();
}

class _ThinkingPageState extends State<ThinkingPage> {
  late final TextEditingController _controller;
  late final TextEditingController _titleController;
  late String _tag;
  late bool _isFavorite;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.thought?.content ?? widget.initialContent ?? '',
    );
    _titleController = TextEditingController(text: widget.thought?.title ?? '');
    final requestedTag = widget.thought?.tag ?? widget.initialTag;

    _tag = requestedTag != null && Thought.tags.contains(requestedTag)
        ? requestedTag
        : Thought.tags.first;
    _isFavorite = widget.thought?.isFavorite ?? false;
  }

  String _formatParagraphs(String text) {
    return text
        .split(RegExp(r'\n\s*\n'))
        .map((paragraph) {
          final content = paragraph.trim();

          if (content.isEmpty) {
            return '';
          }

          return '\u3000\u3000$content';
        })
        .join('\n\n');
  }

  Future<void> _save() async {
    final content = _formatParagraphs(_controller.text.trim());

    if (content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先写下一些内容')));
      return;
    }

    setState(() => _saving = true);

    try {
      final now = DateTime.now();
      final thought = Thought(
        id: widget.thought?.id,
        title: _titleController.text.trim(),
        content: content,
        tag: _tag,
        isFavorite: _isFavorite,
        createdAt: widget.thought?.createdAt ?? now,
        updatedAt: now,
      );

      final onSave = widget.onSave;

      if (onSave == null) {
        await ArkDatabase.instance.saveThought(thought);
      } else {
        await onSave(thought);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.thought != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '编辑记录' : '记录今天'),
        actions: [
          IconButton(
            tooltip: _isFavorite ? '取消收藏' : '收藏',
            onPressed: () => setState(() => _isFavorite = !_isFavorite),
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? Colors.redAccent : null,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今天发生了什么？',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '不用完美，只要真实。',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 7),
              TextField(
                controller: _titleController,
                maxLength: 50,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: '给这条记录起一个标题',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: Thought.tags.map((tag) {
                  final selected = _tag == tag;

                  return ChoiceChip(
                    label: Text(tag),
                    selected: selected,
                    showCheckmark: false,
                    shape: const StadiumBorder(),
                    side: BorderSide(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                    selectedColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    onSelected: (_) {
                      setState(() {
                        _tag = tag;
                      });
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 7),

              Expanded(
                child: TextField(
                  controller: _controller,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  autofocus: !editing,
                  decoration: const InputDecoration(hintText: '写下今天的想法…'),
                ),
              ),

              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(editing ? '保存修改' : '保存记录'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _controller.dispose();
    super.dispose();
  }
}

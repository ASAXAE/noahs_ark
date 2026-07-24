import 'package:flutter/material.dart';

import '../../database/ark_database.dart';
import '../../models/thought.dart';

class ThinkingPage extends StatefulWidget {
  const ThinkingPage({super.key, this.thought});

  final Thought? thought;

  @override
  State<ThinkingPage> createState() => _ThinkingPageState();
}

class _ThinkingPageState extends State<ThinkingPage> {
  late final TextEditingController _controller;
  late String _tag;
  late bool _isFavorite;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.thought?.content ?? '');
    _tag = widget.thought?.tag ?? Thought.tags.first;
    _isFavorite = widget.thought?.isFavorite ?? false;
  }

  Future<void> _save() async {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先写下一些内容')));
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    await ArkDatabase.instance.saveThought(
      Thought(
        id: widget.thought?.id,
        content: content,
        tag: _tag,
        isFavorite: _isFavorite,
        createdAt: widget.thought?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    if (!mounted) return;
    Navigator.pop(context, true);
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
              const SizedBox(height: 20),
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
              DropdownButtonFormField<String>(
                initialValue: _tag,
                decoration: const InputDecoration(
                  labelText: '标签',
                  prefixIcon: Icon(Icons.sell_outlined),
                ),
                items: Thought.tags
                    .map(
                      (tag) => DropdownMenuItem(value: tag, child: Text(tag)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _tag = value ?? _tag),
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
    _controller.dispose();
    super.dispose();
  }
}

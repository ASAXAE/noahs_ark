import 'package:flutter/material.dart';

import '../../models/thought.dart';
import '../thinking/thinking_page.dart';

class ThoughtDetailPage extends StatelessWidget {
  const ThoughtDetailPage({
    super.key,
    required this.thought,
  });

  final Thought thought;

  Future<void> _openEidtor(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ThinkingPage(thought: thought,),
      ),
    );

    if(changed == true && context.mounted) {
      Navigator.pop(context,true);
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
            onPressed: () => _openEidtor(context),
            icon: const Icon(Icons.edit_outlined),
          )
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
                  style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(
                      fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 14),

                Row(
                  children: [
                    Chip(
                      avatar: const Icon(
                        Icons.sell_outlined,
                        size: 18,
                      ),
                      label: Text((thought.tag)),
                    ),

                    const Spacer(),

                    if (thought.isFavorite)
                      const Icon(
                        Icons.favorite,
                        color: Colors.redAccent,
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                Text(
                  thought.formattedDate,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),

                const Divider(height: 40),

                SelectableText(
                  thought.content,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.8,
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }
}

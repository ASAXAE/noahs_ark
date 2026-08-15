import 'package:flutter/material.dart';

import '../models/thought.dart';

class ThoughtCard extends StatelessWidget {
  const ThoughtCard({
    super.key,
    required this.thought,
    required this.isExpanded,
    required this.onTap,
    required this.onToggleExpanded,
    required this.onEdit,
    required this.onFavorite,
    required this.onDelete,
  });

  final Thought thought;
  final bool isExpanded;

  final VoidCallback onTap;
  final VoidCallback onToggleExpanded;
  final VoidCallback onEdit;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final previewContent = thought.content.replaceAll(RegExp(r'\n\s*\n'), '\n');

    final mayOverflow =
        thought.content.length > 70 ||
        '\n'.allMatches(thought.content).length >= 2;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            thought.tag,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Text(
                            thought.title.isEmpty ? '无标题' : thought.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    Text(
                      isExpanded ? thought.content : previewContent,
                      maxLines: isExpanded ? null : 3,
                      overflow: isExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, height: 1.5),
                    ),

                    if (mayOverflow) ...[
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 0,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: onToggleExpanded,
                          child: Text(isExpanded ? '收起' : '显示全文'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),

                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        thought.formattedDate,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (thought.isFavorite)
                const SizedBox(
                  width: 15,
                  height: 48,
                  child: Center(
                    child: Icon(
                      Icons.favorite,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                  ),
                ),

              PopupMenuButton<String>(
                color: Theme.of(context).cardColor,
                elevation: 10,
                offset: const Offset(-8, 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  }

                  if (value == 'favorite') {
                    onFavorite();
                  }

                  if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    height: 46,
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('编辑'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'favorite',
                    height: 46,
                    child: Row(
                      children: [
                        Icon(
                          thought.isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 20,
                          color: thought.isFavorite ? Colors.redAccent : null,
                        ),
                        const SizedBox(width: 12),
                        Text(thought.isFavorite ? '取消' : '收藏'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    height: 46,
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '删除',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

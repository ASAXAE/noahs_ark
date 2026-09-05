import 'package:flutter/material.dart';

import '../../../models/thought.dart';
import '../../../widgets/thought_card.dart';

class HomeThoughtList extends StatelessWidget {
  const HomeThoughtList({
    super.key,
    required this.thoughts,
    required this.expandedThoughtIds,
    required this.onOpen,
    required this.onToggleExpanded,
    required this.onEdit,
    required this.onFavorite,
    required this.onDelete,
  });

  final List<Thought> thoughts;
  final Set<int> expandedThoughtIds;
  final ValueChanged<Thought> onOpen;
  final ValueChanged<int> onToggleExpanded;
  final ValueChanged<Thought> onEdit;
  final ValueChanged<Thought> onFavorite;
  final ValueChanged<Thought> onDelete;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      sliver: SliverList.separated(
        itemCount: thoughts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) {
          final thought = thoughts[index];
          final id = thought.id;

          return ThoughtCard(
            thought: thought,
            isExpanded: id != null && expandedThoughtIds.contains(id),
            onTap: () => onOpen(thought),
            onToggleExpanded: () {
              if (id != null) {
                onToggleExpanded(id);
              }
            },
            onEdit: () => onEdit(thought),
            onFavorite: () => onFavorite(thought),
            onDelete: () => onDelete(thought),
          );
        },
      ),
    );
  }
}
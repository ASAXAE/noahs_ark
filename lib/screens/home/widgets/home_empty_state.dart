import 'package:flutter/material.dart';

class HomeEmptyState extends StatelessWidget {
  const HomeEmptyState({
    super.key,
    required this.searchText,
    required this.selectedTag,
    required this.favoritesOnly,
    required this.onResetFilters,
    required this.onCreateThought,
  });

  final String searchText;
  final String? selectedTag;
  final bool favoritesOnly;
  final VoidCallback onResetFilters;
  final VoidCallback onCreateThought;

  @override
  Widget build(BuildContext context) {
    final normalizedSearch = searchText.trim();
    final hasActiveFilters =
        normalizedSearch.isNotEmpty || selectedTag != null || favoritesOnly;

    String title;
    String description;
    IconData icon;

    if (normalizedSearch.isNotEmpty) {
      title = '没有找到相关记录';
      description = '试试修改搜索内容';
      icon = Icons.search_off_outlined;
    } else if (selectedTag != null) {
      title = '“$selectedTag”标签还没有记录';
      description = '你可以写下一条属于这个标签的想法';
      icon = Icons.label_outline;
    } else if (favoritesOnly) {
      title = '还没有收藏记录';
      description = '收藏重要的想法后，它们会出现在这里';
      icon = Icons.favorite_border;
    } else {
      title = '方舟还是空的';
      description = '写下此刻值得保存的想法';
      icon = Icons.auto_stories_outlined;
    }

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
              onPressed: hasActiveFilters ? onResetFilters : onCreateThought,
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
}

import 'package:flutter/material.dart';

class HomeFilters extends StatelessWidget {
  const HomeFilters({
    super.key,
    required this.searchController,
    required this.hasSearchText,
    required this.selectedTag,
    required this.tags,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onTagSelected,
  });

  final TextEditingController searchController;
  final bool hasSearchText;
  final String? selectedTag;
  final List<String> tags;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String?> onTagSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: '搜索记录',
            suffixIcon: hasSearchText
                ? IconButton(
                    tooltip: '清空搜索',
                    onPressed: onClearSearch,
                    icon: const Icon(Icons.close),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: selectedTag == null,
                onSelected: (_) => onTagSelected(null),
              ),
              for (final tag in tags) ...[
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(tag),
                  selected: selectedTag == tag,
                  onSelected: (_) => onTagSelected(tag),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

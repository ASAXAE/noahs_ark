import 'package:flutter/material.dart';

import '../../database/ark_database.dart';
import '../../models/thought.dart';
import '../thinking/thinking_page.dart';
import '../detail/thought_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  final Set<int> _expandedThoughtIds = {};
  List<Thought> _thoughts = [];
  bool _loading = true;
  bool _favoritesOnly = false;
  bool _hasSearchText = false;
  String? _selectedTag;

  @override
  void initState() {
    super.initState();
    _loadThoughts();
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
      MaterialPageRoute(builder: (_) => ThinkingPage(thought: thought)),
    );
    if (changed == true) await _loadThoughts();
  }

  Future<void> _openDetail(Thought thought) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ThoughtDetailPage(
              thought: thought,
            ),
      ),
    );

    if (changed == true) {
      await _loadThoughts();
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
      builder: (context) =>
          AlertDialog(
            title: const Text('删除这条记录？'),
            content: const Text('删除后无法恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (confirmed != true || thought.id == null) return;
    await ArkDatabase.instance.deleteThought(thought.id!);
    await _loadThoughts();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '诺亚方舟',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
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
                  children: [_hero(), const SizedBox(height: 20), _filters()],
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                if (_thoughts.isEmpty)
                  SliverFillRemaining(
                      hasScrollBody: false, child: _emptyState())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    sliver: SliverList.separated(
                      itemCount: _thoughts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, index) => _thoughtCard(_thoughts[index]),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() =>
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF426B5A),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('今日思考', style: TextStyle(color: Colors.white70)),
                  SizedBox(height: 6),
                  Text(
                    '把重要的想法留下来',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              child: const Icon(Icons.sailing, color: Colors.white, size: 30),
            ),
          ],
        ),
      );

  Widget _filters() =>
      Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _hasSearchText = value.isNotEmpty;
              });

              _loadThoughts();
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: '搜索记录',
              suffixIcon: _hasSearchText
                  ? IconButton(
                tooltip: '清空搜索',
                onPressed: _clearSearch,
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
                  selected: _selectedTag == null,
                  onSelected: (_) {
                    setState(() => _selectedTag = null);
                    _loadThoughts();
                  },
                ),
                for (final tag in Thought.tags) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(tag),
                    selected: _selectedTag == tag,
                    onSelected: (_) {
                      setState(() => _selectedTag = tag);
                      _loadThoughts();
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      );

  Widget _emptyState() =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_stories_outlined,
                size: 64,
                color: Theme
                    .of(context)
                    .colorScheme
                    .outline,
              ),
              const SizedBox(height: 16),
              Text(
                _searchController.text.isEmpty
                    ? '方舟还是空的'
                    : '没有找到相关记录',
                style: Theme
                    .of(context)
                    .textTheme
                    .titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '写下此刻值得保存的想法',
                style: TextStyle(color: Theme
                    .of(context)
                    .colorScheme
                    .outline),
              ),
            ],
          ),
        ),
      );

  Widget _thoughtCard(Thought thought) {
    final id = thought.id;
    final isExpanded = id != null && _expandedThoughtIds.contains(id);

    final previewContent = thought.content.replaceAll(RegExp(r'\n\s*\n'), '\n');

    final mayOverflow =
        thought.content.length > 70 ||
            '\n'
                .allMatches(thought.content)
                .length >= 2;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(thought),
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
                            color: Theme
                                .of(
                              context,
                            )
                                .colorScheme
                                .secondaryContainer,
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

                    if (mayOverflow && id != null) ...[
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
                          onPressed: () => _toggleThoughtExpanded(id),
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
                          color: Theme
                              .of(context)
                              .colorScheme
                              .outline,
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
                onSelected: (value) {
                  if (value == 'favorite') {
                    _toggleFavorite(thought);
                  }

                  if (value == 'delete') {
                    _delete(thought);
                  }
                },
                itemBuilder: (_) =>
                [
                  PopupMenuItem(
                    value: 'favorite',
                    child: Text(thought.isFavorite ? '取消收藏' : '收藏'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
        ),
      ),
    );
  } // _thoughtCard 在这里结束

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
//Ctrl + Alt + L格式化 Ctrl + F当前文件搜索 Ctrl + Shift + F整个项目搜索 Ctrl + Shift + N 快速打开文件 Ctrl + F12查看当前文件结构
//fn + esc 转换f1-f12
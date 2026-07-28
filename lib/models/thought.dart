class Thought {
  const Thought({
    this.id,
    required this.title,
    required this.content,
    required this.tag,
    required this.createdAt,
    required this.updatedAt,
    this.isFavorite = false,
  });

  static const tags = ['成长', '灵感', '梦想', '生活', '学习'];

  final int? id;
  final String title;
  final String content;
  final String tag;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorite;

  String get formattedDate {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${createdAt.year}/${two(createdAt.month)}/${two(createdAt.day)} ${two(createdAt.hour)}:${two(createdAt.minute)}';
  }

  Thought copyWith({
    String? title,
    String? content,
    String? tag,
    bool? isFavorite,
  }) => Thought(
    id: id,
    title: title ?? this.title,
    content: content ?? this.content,
    tag: tag ?? this.tag,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    isFavorite: isFavorite ?? this.isFavorite,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'content': content,
    'tag': tag,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_favorite': isFavorite ? 1 : 0,
  };

  factory Thought.fromMap(Map<String, Object?> map) => Thought(
    id: map['id'] as int,
    title: map['title'] as String,
    content: map['content'] as String,
    tag: map['tag'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
    isFavorite: map['is_favorite'] == 1,
  );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'tag': tag,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isFavorite': isFavorite,
    };
  }

  factory Thought.fromJson(Map<String, dynamic> json) {
    return Thought(
      id: json['id'] as int?,
      title: json['title'] as String? ?? '',
      content: json['content'] as String,
      tag: json['tag'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
  }
}

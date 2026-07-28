import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/thought.dart';

void main() {
  test('Thought can convert to JSON and back', () {
    final original = Thought(
      id: 10,
      title: 'Day 10',
      content: '今天学习 JSON',
      tag: '成长',
      createdAt: DateTime(2026, 7, 28, 10, 30),
      updatedAt: DateTime(2026, 7, 28, 10, 35),
      isFavorite: true,
    );

    final jsonText = jsonEncode(original.toJson());

    final decodedJson = jsonDecode(jsonText) as Map<String, dynamic>;

    final restored = Thought.fromJson(decodedJson);

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.content, original.content);
    expect(restored.tag, original.tag);
    expect(restored.createdAt, original.createdAt);
    expect(restored.updatedAt, original.updatedAt);
    expect(restored.isFavorite, original.isFavorite);
  });
}

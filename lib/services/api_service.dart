import 'dart:convert';
import '../models/thought.dart';

import 'package:http/http.dart' as http;

class ApiService {
  static const String _exampleUrl =
      'https://jsonplaceholder.typicode.com/todos/1';

  Future<String> fetchExampleTitle() async {
    final uri = Uri.parse(_exampleUrl);

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    return json['title'] as String;
  }

  static const String _localBaseUrl = 'http://127.0.0.1:3000';

  Future<String> fetchHealthMessage() async {
    final uri = Uri.parse('$_localBaseUrl/health');

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;

    return json['message'] as String;
  }

  Future<List<Thought>> fetchThoughts() async {
    final uri = Uri.parse('$_localBaseUrl/thoughts');

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final jsonList =
        jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;

    return jsonList
        .map((json) => Thought.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Thought> createTestThought() async {
    final uri = Uri.parse('$_localBaseUrl/thoughts');

    final requestBody = jsonEncode({
      'title': 'Day 16 API 测试',
      'content': '这是一条由 Flutter 创建的服务器测试记录',
      'tag': '学习',
    });

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: requestBody,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 201) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    return Thought.fromJson(json);
  }

  Future<Thought> updateThought(Thought thought) async {
    final id = thought.id;

    if (id == null) {
      throw ArgumentError('Thought id cannot be null');
    }

    final uri = Uri.parse('$_localBaseUrl/thoughts/$id');

    final requestBody = jsonEncode({
      'title': thought.title,
      'content': thought.content,
      'tag': thought.tag,
      'isFavorite': thought.isFavorite,
    });

    final response = await http
        .patch(
          uri,
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: requestBody,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    return Thought.fromJson(json);
  }

  Future<void> deleteThought(int id) async {
    final uri = Uri.parse('$_localBaseUrl/thoughts/$id');

    final response = await http
        .delete(uri)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 204) {
      throw Exception('HTTP ${response.statusCode}');
    }
  }
}

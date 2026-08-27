import 'dart:convert';
import '../models/auth_session.dart';
import '../models/auth_user.dart';
import '../models/thought.dart';
import 'api_exception.dart';
import 'auth_session_storage.dart';

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

  static const String _localBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );

  Future<Map<String, String>> _authenticatedHeaders({
    bool includeJsonContentType = false,
  }) async {
    final accessToken = await AuthSessionStorage.instance.readAccessToken();

    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException(statusCode: 401, message: '请先登录');
    }

    return {
      if (includeJsonContentType)
        'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $accessToken',
    };
  }

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

    final headers = await _authenticatedHeaders();

    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 10));

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
    final headers = await _authenticatedHeaders(includeJsonContentType: true);

    final requestBody = jsonEncode({
      'title': 'Day 16 API 测试',
      'content': '这是一条由 Flutter 创建的服务器测试记录',
      'tag': '学习',
    });

    final response = await http
        .post(uri, headers: headers, body: requestBody)
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
    final headers = await _authenticatedHeaders(includeJsonContentType: true);

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
        .patch(uri, headers: headers, body: requestBody)
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
    final headers = await _authenticatedHeaders();

    final response = await http
        .delete(uri, headers: headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 204) {
      throw Exception('HTTP ${response.statusCode}');
    }
  }

  Future<AuthUser> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$_localBaseUrl/auth/register');

    final requestBody = jsonEncode({
      'displayName': displayName.trim(),
      'email': email.trim(),
      'password': password,
    });

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: requestBody,
        )
        .timeout(const Duration(seconds: 10));

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode != 201) {
      final message = json['message'] as String? ?? '注册失败';

      throw Exception(message);
    }

    return AuthUser.fromJson(json);
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$_localBaseUrl/auth/login');

    final requestBody = jsonEncode({
      'email': email.trim(),
      'password': password,
    });

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: requestBody,
        )
        .timeout(const Duration(seconds: 10));

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final message = json['message'] as String? ?? '登录失败';
      throw Exception(message);
    }

    return AuthSession.fromJson(json);
  }

  Future<AuthUser> fetchCurrentUser({required String accessToken}) async {
    final uri = Uri.parse('$_localBaseUrl/auth/me');

    final response = await http
        .get(uri, headers: {'Authorization': 'Bearer $accessToken'})
        .timeout(const Duration(seconds: 10));

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final message = json['message'] as String? ?? '获取用户信息失败';

      throw ApiException(statusCode: response.statusCode, message: message);
    }

    return AuthUser.fromJson(json);
  }
}

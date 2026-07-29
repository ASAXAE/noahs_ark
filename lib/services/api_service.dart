import 'dart:convert';

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
}

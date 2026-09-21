import 'dart:convert';
import '../models/auth_session.dart';
import '../models/auth_user.dart';
import '../models/thought.dart';
import '../models/auth_tokens.dart';
import 'api_exception.dart';
import 'auth_token_coordinator.dart';

import 'package:http/http.dart' as http;

class ApiService {
  ApiService({
    http.Client? httpClient,
    AuthTokenCoordinator? authTokenCoordinator,
  }) : _httpClient = httpClient ?? _sharedHttpClient,
       _authTokenCoordinator =
           authTokenCoordinator ?? AuthTokenCoordinator.instance;

  static final http.Client _sharedHttpClient = http.Client();

  final http.Client _httpClient;
  final AuthTokenCoordinator _authTokenCoordinator;
  static const String _exampleUrl =
      'https://jsonplaceholder.typicode.com/todos/1';

  Future<String> fetchExampleTitle() async {
    final uri = Uri.parse(_exampleUrl);

    final response = await _httpClient
        .get(uri)
        .timeout(const Duration(seconds: 10));

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

  Future<http.Response> _sendAuthenticated({
    required String method,
    required Uri uri,
    String? body,
    bool includeJsonContentType = false,
  }) async {
    Future<http.Response> send(String accessToken) {
      final headers = {
        if (includeJsonContentType)
          'Content-Type': 'application/json; charset=UTF-8',
        'Authorization': 'Bearer $accessToken',
      };

      late final Future<http.Response> request;

      switch (method) {
        case 'GET':
          request = _httpClient.get(uri, headers: headers);
        case 'POST':
          request = _httpClient.post(uri, headers: headers, body: body);
        case 'PATCH':
          request = _httpClient.patch(uri, headers: headers, body: body);
        case 'DELETE':
          request = _httpClient.delete(uri, headers: headers);
        default:
          throw ArgumentError.value(
            method,
            'method',
            'Unsupported HTTP method',
          );
      }

      return request.timeout(const Duration(seconds: 10));
    }

    final rejectedAccessToken = await _authTokenCoordinator.readAccessToken();

    var response = await send(rejectedAccessToken);

    if (response.statusCode != 401) {
      return response;
    }

    final refreshedTokens = await _authTokenCoordinator
        .refreshAfterUnauthorized(
          rejectedAccessToken: rejectedAccessToken,
          refresh: (refreshToken) {
            return refreshTokens(refreshToken: refreshToken);
          },
        );

    response = await send(refreshedTokens.accessToken);

    if (response.statusCode == 401) {
      await _authTokenCoordinator.clearSession();
    }

    return response;
  }

  Future<String> fetchHealthMessage() async {
    final uri = Uri.parse('$_localBaseUrl/health');

    final response = await _httpClient
        .get(uri)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;

    return json['message'] as String;
  }

  Future<List<Thought>> fetchThoughts() async {
    final uri = Uri.parse('$_localBaseUrl/thoughts');

    final response = await _sendAuthenticated(method: 'GET', uri: uri);

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

    final response = await _sendAuthenticated(
      method: 'POST',
      uri: uri,
      body: requestBody,
      includeJsonContentType: true,
    );

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

    final response = await _sendAuthenticated(
      method: 'PATCH',
      uri: uri,
      body: requestBody,
      includeJsonContentType: true,
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    return Thought.fromJson(json);
  }

  Future<void> deleteThought(int id) async {
    final uri = Uri.parse('$_localBaseUrl/thoughts/$id');

    final response = await _sendAuthenticated(method: 'DELETE', uri: uri);

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

    final response = await _httpClient
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

    final response = await _httpClient
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

  Future<AuthTokens> refreshTokens({required String refreshToken}) async {
    final uri = Uri.parse('$_localBaseUrl/auth/token/refresh');

    final response = await _httpClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: jsonEncode({'refreshToken': refreshToken}),
        )
        .timeout(const Duration(seconds: 10));

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final message = json['message'] as String? ?? 'Failed to refresh session';

      throw ApiException(statusCode: response.statusCode, message: message);
    }

    return AuthTokens.fromJson(json);
  }

  Future<void> logout({required String refreshToken}) async {
    final uri = Uri.parse('$_localBaseUrl/auth/logout');

    final response = await _httpClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: jsonEncode({'refreshToken': refreshToken}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 204) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to log out',
      );
    }
  }

  Future<AuthUser> fetchCurrentUser({required String accessToken}) async {
    final uri = Uri.parse('$_localBaseUrl/auth/me');

    final response = await _httpClient
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

  Future<void> resendVerificationEmail() async {
    final uri = Uri.parse('$_localBaseUrl/auth/email-verification/resend');

    final response = await _sendAuthenticated(method: 'POST', uri: uri);

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode != 202) {
      final message =
          json['message'] as String? ?? 'Verification email request failed';

      throw ApiException(statusCode: response.statusCode, message: message);
    }
  }

  Future<void> confirmEmailVerification({required String token}) async {
    final normalizedToken = token.trim();

    if (normalizedToken.isEmpty) {
      throw const ApiException(
        statusCode: 400,
        message: 'Invalid or expired verification token',
      );
    }

    final uri = Uri.parse('$_localBaseUrl/auth/email-verification/confirm');

    final response = await _httpClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: jsonEncode({'token': normalizedToken}),
        )
        .timeout(const Duration(seconds: 10));

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final message =
          json['message'] as String? ?? 'Failed to confirm email verification';

      throw ApiException(statusCode: response.statusCode, message: message);
    }

    if (json['verified'] != true) {
      throw const FormatException('Email verification response is invalid');
    }
  }

  Future<void> requestPasswordReset({required String email}) async {
    final normalizedEmail = email.trim().toLowerCase();

    if (normalizedEmail.isEmpty) {
      throw const ApiException(
        statusCode: 400,
        message: 'Invalid password reset request',
      );
    }

    final uri = Uri.parse('$_localBaseUrl/auth/password-reset/request');

    final response = await _httpClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: jsonEncode({'email': normalizedEmail}),
        )
        .timeout(const Duration(seconds: 10));

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode != 202) {
      final message =
          json['message'] as String? ?? 'Password reset request failed';

      throw ApiException(statusCode: response.statusCode, message: message);
    }
  }

  Future<void> confirmPasswordReset({
    required String token,
    required String password,
  }) async {
    final normalizedToken = token.trim().toLowerCase();

    if (normalizedToken.isEmpty || password.isEmpty) {
      throw const ApiException(
        statusCode: 400,
        message: 'Invalid password reset data',
      );
    }

    final uri = Uri.parse('$_localBaseUrl/auth/password-reset/confirm');

    final response = await _httpClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: jsonEncode({'token': normalizedToken, 'password': password}),
        )
        .timeout(const Duration(seconds: 10));

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final message = json['message'] as String? ?? 'Failed to reset password';

      throw ApiException(statusCode: response.statusCode, message: message);
    }

    if (json['reset'] != true) {
      throw const FormatException('Password reset response is invalid');
    }
  }
}

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_tokens.dart';

class AuthSessionStorage {
  AuthSessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static final AuthSessionStorage instance = AuthSessionStorage();

  static const String _tokenBundleKey = 'auth_token_bundle';
  static const String _legacyAccessTokenKey = 'auth_access_token';

  final FlutterSecureStorage _storage;

  Future<void> saveTokens(AuthTokens tokens) async {
    if (tokens.accessToken.isEmpty) {
      throw ArgumentError('Access token cannot be empty');
    }

    if (tokens.refreshToken.isEmpty) {
      throw ArgumentError('Refresh token cannot be empty');
    }

    await _storage.write(
      key: _tokenBundleKey,
      value: jsonEncode(tokens.toJson()),
    );

    await _storage.delete(key: _legacyAccessTokenKey);
  }

  Future<AuthTokens?> readTokens() async {
    final storedValue = await _storage.read(key: _tokenBundleKey);

    if (storedValue == null || storedValue.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(storedValue);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Stored session is invalid');
      }

      return AuthTokens.fromJson(decoded);
    } on FormatException {
      await _storage.delete(key: _tokenBundleKey);
      return null;
    }
  }

  Future<void> saveAccessToken(String accessToken) async {
    if (accessToken.isEmpty) {
      throw ArgumentError('Access token cannot be empty');
    }

    await _storage.write(key: _legacyAccessTokenKey, value: accessToken);
  }

  Future<String?> readAccessToken() async {
    final tokens = await readTokens();

    if (tokens != null) {
      return tokens.accessToken;
    }

    return _storage.read(key: _legacyAccessTokenKey);
  }

  Future<void> deleteTokens() async {
    await _storage.delete(key: _tokenBundleKey);
    await _storage.delete(key: _legacyAccessTokenKey);
  }

  Future<void> deleteAccessToken() {
    return deleteTokens();
  }
}

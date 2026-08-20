import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthSessionStorage {
  AuthSessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static final AuthSessionStorage instance = AuthSessionStorage();

  static const String _accessTokenKey = 'auth_access_token';

  final FlutterSecureStorage _storage;

  Future<void> saveAccessToken(String accessToken) async {
    if (accessToken.isEmpty) {
      throw ArgumentError('Access token cannot be empty');
    }

    await _storage.write(key: _accessTokenKey, value: accessToken);
  }

  Future<String?> readAccessToken() {
    return _storage.read(key: _accessTokenKey);
  }

  Future<void> deleteAccessToken() {
    return _storage.delete(key: _accessTokenKey);
  }
}

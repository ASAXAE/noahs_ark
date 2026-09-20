import '../models/auth_tokens.dart';
import 'api_exception.dart';
import 'auth_session_storage.dart';

typedef RefreshTokensCallback =
    Future<AuthTokens> Function(String refreshToken);

class AuthTokenCoordinator {
  AuthTokenCoordinator({AuthSessionStorage? storage})
    : _storage = storage ?? AuthSessionStorage.instance;

  static final AuthTokenCoordinator instance = AuthTokenCoordinator();

  final AuthSessionStorage _storage;

  Future<AuthTokens>? _refreshInFlight;

  Future<String> readAccessToken() async {
    final tokens = await _readUsableTokens();
    return tokens.accessToken;
  }

  Future<AuthTokens> refreshAfterUnauthorized({
    required String rejectedAccessToken,
    required RefreshTokensCallback refresh,
  }) async {
    final existingRefresh = _refreshInFlight;

    if (existingRefresh != null) {
      return existingRefresh;
    }

    final operation = _refreshAndPersist(
      rejectedAccessToken: rejectedAccessToken,
      refresh: refresh,
    );

    _refreshInFlight = operation;

    try {
      return await operation;
    } finally {
      if (identical(_refreshInFlight, operation)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<void> clearSession() {
    return _storage.deleteTokens();
  }

  Future<AuthTokens> _readUsableTokens() async {
    final tokens = await _storage.readTokens();

    if (tokens == null) {
      throw const ApiException(
        statusCode: 401,
        message: 'Authentication required',
      );
    }

    if (tokens.isRefreshTokenExpiredAt(DateTime.now())) {
      await _storage.deleteTokens();

      throw const ApiException(
        statusCode: 401,
        message: 'Invalid or expired refresh token',
      );
    }

    return tokens;
  }

  Future<AuthTokens> _refreshAndPersist({
    required String rejectedAccessToken,
    required RefreshTokensCallback refresh,
  }) async {
    final currentTokens = await _readUsableTokens();

    if (currentTokens.accessToken != rejectedAccessToken) {
      return currentTokens;
    }

    late final AuthTokens refreshedTokens;

    try {
      refreshedTokens = await refresh(currentTokens.refreshToken);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _storage.deleteTokens();
      }

      rethrow;
    }

    if (refreshedTokens.isRefreshTokenExpiredAt(DateTime.now())) {
      await _storage.deleteTokens();

      throw const ApiException(
        statusCode: 401,
        message: 'Invalid or expired refresh token',
      );
    }

    try {
      await _storage.saveTokens(refreshedTokens);
    } catch (_) {
      await _storage.deleteTokens();
      rethrow;
    }

    return refreshedTokens;
  }
}

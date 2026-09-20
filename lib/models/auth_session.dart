import 'auth_tokens.dart';
import 'auth_user.dart';

class AuthSession {
  const AuthSession({required this.tokens, required this.user});

  final AuthTokens tokens;
  final AuthUser user;

  String get accessToken => tokens.accessToken;

  String get refreshToken => tokens.refreshToken;

  DateTime get refreshTokenExpiresAt => tokens.refreshTokenExpiresAt;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];

    if (rawUser is! Map<String, dynamic>) {
      throw const FormatException(
        'Login response does not contain a valid user',
      );
    }

    return AuthSession(
      tokens: AuthTokens.fromJson(json),
      user: AuthUser.fromJson(rawUser),
    );
  }

  AuthSession withUser(AuthUser updatedUser) {
    return AuthSession(tokens: tokens, user: updatedUser);
  }
}

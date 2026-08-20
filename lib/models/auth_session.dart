import 'auth_user.dart';

class AuthSession {
  const AuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final rawAccessToken = json['accessToken'];
    final rawUser = json['user'];

    if (rawAccessToken is! String || rawAccessToken.isEmpty) {
      throw const FormatException(
        'Login response does not contain an access token',
      );
    }

    if (rawUser is! Map<String, dynamic>) {
      throw const FormatException(
        'Login response does not contain a valid user',
      );
    }

    return AuthSession(
      accessToken: rawAccessToken,
      user: AuthUser.fromJson(rawUser),
    );
  }
}

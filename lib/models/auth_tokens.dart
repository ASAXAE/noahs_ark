class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    final rawAccessToken = json['accessToken'];
    final rawRefreshToken = json['refreshToken'];
    final rawExpiresAt = json['refreshTokenExpiresAt'];

    if (rawAccessToken is! String || rawAccessToken.isEmpty) {
      throw const FormatException('Session does not contain an access token');
    }

    if (rawRefreshToken is! String || rawRefreshToken.isEmpty) {
      throw const FormatException('Session does not contain a refresh token');
    }

    if (rawExpiresAt is! String) {
      throw const FormatException(
        'Session does not contain a refresh token expiry',
      );
    }

    final expiresAt = DateTime.tryParse(rawExpiresAt);

    if (expiresAt == null) {
      throw const FormatException('Refresh token expiry is invalid');
    }

    return AuthTokens(
      accessToken: rawAccessToken,
      refreshToken: rawRefreshToken,
      refreshTokenExpiresAt: expiresAt.toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'refreshTokenExpiresAt': refreshTokenExpiresAt.toUtc().toIso8601String(),
    };
  }

  bool isRefreshTokenExpiredAt(DateTime time) {
    return !refreshTokenExpiresAt.isAfter(time.toUtc());
  }
}

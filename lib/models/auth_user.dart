class AuthUser {
  const AuthUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.emailVerifiedAt,
    required this.createdAt,
  });

  final int id;
  final String displayName;
  final String email;
  final DateTime? emailVerifiedAt;
  final DateTime createdAt;

  bool get isEmailVerified => emailVerifiedAt != null;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawEmailVerifiedAt = json['emailVerifiedAt'];

    return AuthUser(
      id: rawId is int ? rawId : int.parse(rawId.toString()),
      displayName: json['displayName'] as String,
      email: json['email'] as String,
      emailVerifiedAt: rawEmailVerifiedAt == null
          ? null
          : DateTime.parse(rawEmailVerifiedAt as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

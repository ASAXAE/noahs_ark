class AuthUser {
  const AuthUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.createdAt,
  });

  final int id;
  final String displayName;
  final String email;
  final DateTime createdAt;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];

    return AuthUser(
      id: rawId is int ? rawId : int.parse(rawId.toString()),
      displayName: json['displayName'] as String,
      email: json['email'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

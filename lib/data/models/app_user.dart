class AppUser {
  const AppUser({required this.id, required this.email});

  final String id;
  final String email;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(id: json['id'] as String, email: json['email'] as String);
  }
}

enum UserRole { user, admin, creator }

UserRole userRoleFromString(String? value) {
  return UserRole.values.firstWhere(
    (role) => role.name == value,
    orElse: () => UserRole.user,
  );
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.avatarUrl,
    this.mustChangePassword = false,
  });

  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String? avatarUrl;
  final bool mustChangePassword;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      role: userRoleFromString(json['role'] as String?),
      avatarUrl: json['avatar_url'] as String?,
      mustChangePassword: json['must_change_password'] as bool? ?? false,
    );
  }
}

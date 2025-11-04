/// User Entity
/// Represents a user in the domain layer
class UserEntity {
  final String id;
  final String name;
  final String email;
  final String username;
  final String bio;
  final String occupation;
  final String phone;
  final String profileImageUrl;
  final int age;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? fcmToken;
  final DateTime? tokenUpdated;

  const UserEntity({
    required this.id,
    required this.name,
    required this.email,
    required this.username,
    required this.bio,
    required this.occupation,
    required this.phone,
    required this.profileImageUrl,
    required this.age,
    required this.createdAt,
    required this.updatedAt,
    this.fcmToken,
    this.tokenUpdated,
  });

  UserEntity copyWith({
    String? id,
    String? name,
    String? email,
    String? username,
    String? bio,
    String? occupation,
    String? phone,
    String? profileImageUrl,
    int? age,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? fcmToken,
    DateTime? tokenUpdated,
  }) {
    return UserEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      occupation: occupation ?? this.occupation,
      phone: phone ?? this.phone,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      age: age ?? this.age,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      fcmToken: fcmToken ?? this.fcmToken,
      tokenUpdated: tokenUpdated ?? this.tokenUpdated,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserEntity && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'UserEntity(id: $id, name: $name, email: $email)';
}

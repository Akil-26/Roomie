class UserModel {
  final String uid;
  final String email;
  final String? name;
  final String? username;
  final String? phone;
  final bool isPhoneVerified;
  final String? bio;
  final String? profileImageUrl;
  final String? occupation;
  final int? age;
  final String? upiId; // UPI ID in format: username@bank
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserModel({
    required this.uid,
    required this.email,
    this.name,
    this.username,
    this.phone,
    this.isPhoneVerified = false,
    this.bio,
    this.profileImageUrl,
    this.occupation,
    this.age,
    this.upiId,
    this.createdAt,
    this.updatedAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String uid) {
    return UserModel(
      uid: uid,
      email: map['email'] ?? '',
      name: map['name'],
      username: map['username'],
      phone: map['phone'],
      isPhoneVerified: map['isPhoneVerified'] ?? false,
      bio: map['bio'],
      profileImageUrl: map['profileImageUrl'],
      occupation: map['occupation'],
      age: map['age'],
      upiId: map['upiId'],
      createdAt: map['createdAt']?.toDate(),
      updatedAt: map['updatedAt']?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'username': username,
      'phone': phone,
      'isPhoneVerified': isPhoneVerified,
      'bio': bio,
      'profileImageUrl': profileImageUrl,
      'occupation': occupation,
      'age': age,
      'upiId': upiId,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  String get displayName {
    if (username != null && username!.isNotEmpty) return username!;
    if (name != null && name!.isNotEmpty) return name!;
    return email.split('@')[0]; // Fallback to email username
  }

  String get displayBio {
    if (bio != null && bio!.isNotEmpty) return bio!;
    return 'No bio available';
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? name,
    String? username,
    String? phone,
    bool? isPhoneVerified,
    String? bio,
    String? profileImageUrl,
    String? occupation,
    int? age,
    String? upiId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      name: name ?? this.name,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
      bio: bio ?? this.bio,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      occupation: occupation ?? this.occupation,
      age: age ?? this.age,
      upiId: upiId ?? this.upiId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

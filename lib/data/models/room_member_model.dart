import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents the link between a User and a Room.
/// This controls who is currently inside a room, NOT whether the room exists.
/// 
/// When a user leaves a room:
/// - DO NOT delete the room
/// - DO NOT delete this record
/// - Set isActive = false
/// - Set leftAt = timestamp
class RoomMemberModel {
  final String id; // Unique ID for this membership record
  final String roomId; // Reference to the room/group
  final String userId; // Reference to the user
  final String role; // 'admin' | 'member'
  final DateTime joinedAt;
  final DateTime? leftAt; // Nullable - set when user leaves
  final bool isActive; // false when user has left

  const RoomMemberModel({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.leftAt,
    this.isActive = true,
  });

  /// Create from Firestore document
  factory RoomMemberModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RoomMemberModel.fromMap(data, doc.id);
  }

  /// Create from Map with document ID
  factory RoomMemberModel.fromMap(Map<String, dynamic> map, String id) {
    return RoomMemberModel(
      id: id,
      roomId: map['roomId'] ?? '',
      userId: map['userId'] ?? '',
      role: map['role'] ?? 'member',
      joinedAt: map['joinedAt'] is Timestamp
          ? (map['joinedAt'] as Timestamp).toDate()
          : DateTime.tryParse(map['joinedAt']?.toString() ?? '') ?? DateTime.now(),
      leftAt: map['leftAt'] is Timestamp
          ? (map['leftAt'] as Timestamp).toDate()
          : map['leftAt'] != null
              ? DateTime.tryParse(map['leftAt'].toString())
              : null,
      isActive: map['isActive'] ?? true,
    );
  }

  /// Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'roomId': roomId,
      'userId': userId,
      'role': role,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'leftAt': leftAt != null ? Timestamp.fromDate(leftAt!) : null,
      'isActive': isActive,
    };
  }

  /// Create a copy with updated fields
  RoomMemberModel copyWith({
    String? id,
    String? roomId,
    String? userId,
    String? role,
    DateTime? joinedAt,
    DateTime? leftAt,
    bool? isActive,
  }) {
    return RoomMemberModel(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
      leftAt: leftAt ?? this.leftAt,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Mark member as having left the room
  RoomMemberModel markAsLeft() {
    return copyWith(
      isActive: false,
      leftAt: DateTime.now(),
    );
  }

  /// Rejoin the room (reactivate membership)
  RoomMemberModel rejoin() {
    return copyWith(
      isActive: true,
      leftAt: null,
      joinedAt: DateTime.now(),
    );
  }

  // Helper getters
  bool get isAdmin => role == 'admin';
  bool get isMember => role == 'member';
  bool get hasLeft => !isActive;

  @override
  String toString() {
    return 'RoomMemberModel(id: $id, roomId: $roomId, userId: $userId, role: $role, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RoomMemberModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Enum representing the possible roles a user can have in a room
enum RoomRole {
  admin,
  member;

  String get value {
    switch (this) {
      case RoomRole.admin:
        return 'admin';
      case RoomRole.member:
        return 'member';
    }
  }

  static RoomRole fromString(String value) {
    switch (value.toLowerCase()) {
      case 'admin':
        return RoomRole.admin;
      case 'member':
      default:
        return RoomRole.member;
    }
  }
}

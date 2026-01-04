import 'package:cloud_firestore/cloud_firestore.dart';

/// Type of room space - separates owner area from private roommate area
enum RoomSpaceType {
  owner,   // Owner space: rent, maintenance, payments (managed by owner)
  private, // Private space: roommates only (managed by roommates)
}

/// Represents a logical space within a room.
/// 
/// This enables dual-space architecture:
/// - OWNER space: For rent collection, maintenance, owner announcements
/// - PRIVATE space: For roommate-only communication and activities
/// 
/// IMPORTANT:
/// - This is LOGIC ONLY for Step-2 (no UI yet)
/// - Does NOT create separate rooms
/// - Does NOT duplicate data
/// - Room ID remains unchanged
/// - Roommates keep their private space
class RoomSpaceModel {
  final String spaceId;
  final String roomId;
  final RoomSpaceType spaceType;
  final DateTime createdAt;
  final bool isActive;

  const RoomSpaceModel({
    required this.spaceId,
    required this.roomId,
    required this.spaceType,
    required this.createdAt,
    this.isActive = true,
  });

  /// Create from Firestore document
  factory RoomSpaceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RoomSpaceModel.fromMap(data, doc.id);
  }

  /// Create from Map with document ID
  factory RoomSpaceModel.fromMap(Map<String, dynamic> map, String id) {
    return RoomSpaceModel(
      spaceId: id,
      roomId: map['roomId'] ?? '',
      spaceType: _parseSpaceType(map['spaceType']),
      createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
      isActive: map['isActive'] ?? true,
    );
  }

  /// Parse space type string to enum
  static RoomSpaceType _parseSpaceType(dynamic value) {
    if (value == null) return RoomSpaceType.private;
    final typeStr = value.toString().toLowerCase();
    switch (typeStr) {
      case 'owner':
        return RoomSpaceType.owner;
      default:
        return RoomSpaceType.private;
    }
  }

  /// Parse DateTime from various formats
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  /// Convert space type enum to string for Firestore
  String get spaceTypeString {
    switch (spaceType) {
      case RoomSpaceType.owner:
        return 'owner';
      case RoomSpaceType.private:
        return 'private';
    }
  }

  /// Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'roomId': roomId,
      'spaceType': spaceTypeString,
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
    };
  }

  /// Create a copy with updated fields
  RoomSpaceModel copyWith({
    String? spaceId,
    String? roomId,
    RoomSpaceType? spaceType,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return RoomSpaceModel(
      spaceId: spaceId ?? this.spaceId,
      roomId: roomId ?? this.roomId,
      spaceType: spaceType ?? this.spaceType,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Check if this is owner space
  bool get isOwnerSpace => spaceType == RoomSpaceType.owner;

  /// Check if this is private space
  bool get isPrivateSpace => spaceType == RoomSpaceType.private;

  @override
  String toString() {
    return 'RoomSpaceModel(spaceId: $spaceId, roomId: $roomId, '
        'spaceType: $spaceTypeString, isActive: $isActive)';
  }
}

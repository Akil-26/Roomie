import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of a join request
enum JoinRequestStatus {
  pending,
  approved,
  rejected,
}

/// Represents a request from a student to join an owner-created room.
/// 
/// STEP-4: JOIN REQUEST ENTITY
/// 
/// IMPORTANT RULES:
/// - Student can only request rooms where room.isPublic == true
/// - Student must NOT already be a member
/// - Student must NOT be the owner
/// - On approval: USER_ROOM_LINK is created (student becomes member)
/// - On rejection: No side effects, student sees rejection status
/// - No private data exposed before approval
class RoomJoinRequestModel {
  final String requestId;
  final String roomId;
  final String userId; // The student requesting to join
  final JoinRequestStatus status;
  final DateTime requestedAt;
  final DateTime? reviewedAt; // Set when approved or rejected
  final String? reviewedBy; // Owner ID who approved/rejected

  const RoomJoinRequestModel({
    required this.requestId,
    required this.roomId,
    required this.userId,
    required this.status,
    required this.requestedAt,
    this.reviewedAt,
    this.reviewedBy,
  });

  /// Create from Firestore document
  factory RoomJoinRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RoomJoinRequestModel.fromMap(data, doc.id);
  }

  /// Create from Map with document ID
  factory RoomJoinRequestModel.fromMap(Map<String, dynamic> map, String id) {
    return RoomJoinRequestModel(
      requestId: id,
      roomId: map['roomId'] ?? '',
      userId: map['userId'] ?? '',
      status: _parseStatus(map['status']),
      requestedAt: _parseDateTime(map['requestedAt']) ?? DateTime.now(),
      reviewedAt: _parseDateTime(map['reviewedAt']),
      reviewedBy: map['reviewedBy'],
    );
  }

  /// Parse status string to enum
  static JoinRequestStatus _parseStatus(dynamic value) {
    if (value == null) return JoinRequestStatus.pending;
    final statusStr = value.toString().toLowerCase();
    switch (statusStr) {
      case 'approved':
        return JoinRequestStatus.approved;
      case 'rejected':
        return JoinRequestStatus.rejected;
      default:
        return JoinRequestStatus.pending;
    }
  }

  /// Parse DateTime from various formats
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  /// Convert status enum to string for Firestore
  String get statusString {
    switch (status) {
      case JoinRequestStatus.approved:
        return 'approved';
      case JoinRequestStatus.rejected:
        return 'rejected';
      case JoinRequestStatus.pending:
        return 'pending';
    }
  }

  /// Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'roomId': roomId,
      'userId': userId,
      'status': statusString,
      'requestedAt': Timestamp.fromDate(requestedAt),
      'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'reviewedBy': reviewedBy,
    };
  }

  /// Create a copy with updated fields
  RoomJoinRequestModel copyWith({
    String? requestId,
    String? roomId,
    String? userId,
    JoinRequestStatus? status,
    DateTime? requestedAt,
    DateTime? reviewedAt,
    String? reviewedBy,
  }) {
    return RoomJoinRequestModel(
      requestId: requestId ?? this.requestId,
      roomId: roomId ?? this.roomId,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
    );
  }

  /// Check if request is pending
  bool get isPending => status == JoinRequestStatus.pending;

  /// Check if request is approved
  bool get isApproved => status == JoinRequestStatus.approved;

  /// Check if request is rejected
  bool get isRejected => status == JoinRequestStatus.rejected;

  @override
  String toString() {
    return 'RoomJoinRequestModel(requestId: $requestId, roomId: $roomId, '
        'userId: $userId, status: $statusString)';
  }
}

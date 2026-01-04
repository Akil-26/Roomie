import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of an ownership request
enum OwnershipRequestStatus {
  pending,
  approved,
  rejected,
}

/// Represents a request from an owner to claim/manage an existing room.
/// 
/// IMPORTANT RULES:
/// - Owner can only request rooms where room.ownerId == null
/// - Room must have status == 'active'
/// - On approval: room.ownerId is set, room is NOT duplicated
/// - Existing roommates are NOT affected
/// - Room ID NEVER changes
class RoomOwnershipRequestModel {
  final String requestId;
  final String roomId;
  final String ownerId; // The owner requesting to manage this room
  final OwnershipRequestStatus status;
  final DateTime requestedAt;
  final DateTime? approvedAt; // Set when approved
  final DateTime? rejectedAt; // Set when rejected
  final String? reviewedBy; // User ID who approved/rejected

  const RoomOwnershipRequestModel({
    required this.requestId,
    required this.roomId,
    required this.ownerId,
    required this.status,
    required this.requestedAt,
    this.approvedAt,
    this.rejectedAt,
    this.reviewedBy,
  });

  /// Create from Firestore document
  factory RoomOwnershipRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RoomOwnershipRequestModel.fromMap(data, doc.id);
  }

  /// Create from Map with document ID
  factory RoomOwnershipRequestModel.fromMap(Map<String, dynamic> map, String id) {
    return RoomOwnershipRequestModel(
      requestId: id,
      roomId: map['roomId'] ?? '',
      ownerId: map['ownerId'] ?? '',
      status: _parseStatus(map['status']),
      requestedAt: _parseDateTime(map['requestedAt']) ?? DateTime.now(),
      approvedAt: _parseDateTime(map['approvedAt']),
      rejectedAt: _parseDateTime(map['rejectedAt']),
      reviewedBy: map['reviewedBy'],
    );
  }

  /// Parse status string to enum
  static OwnershipRequestStatus _parseStatus(dynamic value) {
    if (value == null) return OwnershipRequestStatus.pending;
    final statusStr = value.toString().toLowerCase();
    switch (statusStr) {
      case 'approved':
        return OwnershipRequestStatus.approved;
      case 'rejected':
        return OwnershipRequestStatus.rejected;
      default:
        return OwnershipRequestStatus.pending;
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
      case OwnershipRequestStatus.approved:
        return 'approved';
      case OwnershipRequestStatus.rejected:
        return 'rejected';
      case OwnershipRequestStatus.pending:
        return 'pending';
    }
  }

  /// Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'roomId': roomId,
      'ownerId': ownerId,
      'status': statusString,
      'requestedAt': Timestamp.fromDate(requestedAt),
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      'rejectedAt': rejectedAt != null ? Timestamp.fromDate(rejectedAt!) : null,
      'reviewedBy': reviewedBy,
    };
  }

  /// Create a copy with updated fields
  RoomOwnershipRequestModel copyWith({
    String? requestId,
    String? roomId,
    String? ownerId,
    OwnershipRequestStatus? status,
    DateTime? requestedAt,
    DateTime? approvedAt,
    DateTime? rejectedAt,
    String? reviewedBy,
  }) {
    return RoomOwnershipRequestModel(
      requestId: requestId ?? this.requestId,
      roomId: roomId ?? this.roomId,
      ownerId: ownerId ?? this.ownerId,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      approvedAt: approvedAt ?? this.approvedAt,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
    );
  }

  /// Check if request is pending
  bool get isPending => status == OwnershipRequestStatus.pending;

  /// Check if request is approved
  bool get isApproved => status == OwnershipRequestStatus.approved;

  /// Check if request is rejected
  bool get isRejected => status == OwnershipRequestStatus.rejected;

  @override
  String toString() {
    return 'RoomOwnershipRequestModel(requestId: $requestId, roomId: $roomId, '
        'ownerId: $ownerId, status: $statusString)';
  }
}

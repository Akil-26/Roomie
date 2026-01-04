import 'package:cloud_firestore/cloud_firestore.dart';

/// Payment purpose types
/// IMPORTANT: Payments belong to OWNER SPACE only.
/// Private roommate space must NEVER see or touch payments.
enum PaymentPurpose {
  rent,
  maintenance;

  String get value {
    switch (this) {
      case PaymentPurpose.rent:
        return 'rent';
      case PaymentPurpose.maintenance:
        return 'maintenance';
    }
  }

  static PaymentPurpose fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'maintenance':
        return PaymentPurpose.maintenance;
      case 'rent':
      default:
        return PaymentPurpose.rent;
    }
  }

  String get displayName {
    switch (this) {
      case PaymentPurpose.rent:
        return 'Rent';
      case PaymentPurpose.maintenance:
        return 'Maintenance';
    }
  }
}

/// Payment status types
enum PaymentStatus {
  pending,
  success,
  failed;

  String get value {
    switch (this) {
      case PaymentStatus.pending:
        return 'pending';
      case PaymentStatus.success:
        return 'success';
      case PaymentStatus.failed:
        return 'failed';
    }
  }

  static PaymentStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'success':
        return PaymentStatus.success;
      case 'failed':
        return PaymentStatus.failed;
      case 'pending':
      default:
        return PaymentStatus.pending;
    }
  }

  String get displayName {
    switch (this) {
      case PaymentStatus.pending:
        return 'Pending';
      case PaymentStatus.success:
        return 'Success';
      case PaymentStatus.failed:
        return 'Failed';
    }
  }
}

/// Payment record for room-level payments.
/// 
/// CRITICAL RULES:
/// 1. Payments belong to OWNER SPACE only
/// 2. NOT linked to: room_members, private chat, expenses, groceries
/// 3. Payments are room-level, not roommate-level
/// 4. Roommates only see their OWN payment history
/// 5. Owner sees ALL payment records for the room
class PaymentRecordModel {
  final String paymentId;
  final String roomId;
  final String ownerId;      // Room owner who receives payment
  final String payerId;      // User who made the payment
  final double amount;
  final String currency;
  final PaymentPurpose purpose;
  final PaymentStatus status;
  final DateTime createdAt;
  final String? razorpayPaymentId;  // Razorpay transaction ID
  final String? razorpayOrderId;    // Razorpay order ID
  final String? note;               // Optional payment note
  final DateTime? completedAt;      // When payment was completed

  const PaymentRecordModel({
    required this.paymentId,
    required this.roomId,
    required this.ownerId,
    required this.payerId,
    required this.amount,
    required this.currency,
    required this.purpose,
    required this.status,
    required this.createdAt,
    this.razorpayPaymentId,
    this.razorpayOrderId,
    this.note,
    this.completedAt,
  });

  /// Create from Firestore document
  factory PaymentRecordModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PaymentRecordModel.fromMap(data, doc.id);
  }

  /// Create from Map with document ID
  factory PaymentRecordModel.fromMap(Map<String, dynamic> map, String id) {
    return PaymentRecordModel(
      paymentId: id,
      roomId: map['roomId'] ?? '',
      ownerId: map['ownerId'] ?? '',
      payerId: map['payerId'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency'] ?? 'INR',
      purpose: PaymentPurpose.fromString(map['purpose']),
      status: PaymentStatus.fromString(map['status']),
      createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
      razorpayPaymentId: map['razorpayPaymentId'],
      razorpayOrderId: map['razorpayOrderId'],
      note: map['note'],
      completedAt: _parseDateTime(map['completedAt']),
    );
  }

  /// Parse DateTime from various formats
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  /// Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'roomId': roomId,
      'ownerId': ownerId,
      'payerId': payerId,
      'amount': amount,
      'currency': currency,
      'purpose': purpose.value,
      'status': status.value,
      'createdAt': Timestamp.fromDate(createdAt),
      'razorpayPaymentId': razorpayPaymentId,
      'razorpayOrderId': razorpayOrderId,
      'note': note,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
    };
  }

  /// Copy with new values
  PaymentRecordModel copyWith({
    String? paymentId,
    String? roomId,
    String? ownerId,
    String? payerId,
    double? amount,
    String? currency,
    PaymentPurpose? purpose,
    PaymentStatus? status,
    DateTime? createdAt,
    String? razorpayPaymentId,
    String? razorpayOrderId,
    String? note,
    DateTime? completedAt,
  }) {
    return PaymentRecordModel(
      paymentId: paymentId ?? this.paymentId,
      roomId: roomId ?? this.roomId,
      ownerId: ownerId ?? this.ownerId,
      payerId: payerId ?? this.payerId,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      purpose: purpose ?? this.purpose,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      razorpayPaymentId: razorpayPaymentId ?? this.razorpayPaymentId,
      razorpayOrderId: razorpayOrderId ?? this.razorpayOrderId,
      note: note ?? this.note,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  /// Check if payment is successful
  bool get isSuccess => status == PaymentStatus.success;

  /// Check if payment is pending
  bool get isPending => status == PaymentStatus.pending;

  /// Check if payment failed
  bool get isFailed => status == PaymentStatus.failed;

  /// Get currency symbol
  String get currencySymbol {
    switch (currency.toUpperCase()) {
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'INR':
      default:
        return '₹';
    }
  }

  /// Get formatted amount with currency symbol
  String get formattedAmount => '$currencySymbol${amount.toStringAsFixed(2)}';

  @override
  String toString() {
    return 'PaymentRecordModel(paymentId: $paymentId, roomId: $roomId, payerId: $payerId, amount: $formattedAmount, purpose: ${purpose.displayName}, status: ${status.displayName})';
  }
}

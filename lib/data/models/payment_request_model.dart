import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for payment requests made through chat messages
class PaymentRequestModel {
  final String id;
  final String chatId; // Reference to chat or group
  final String messageId; // Reference to the message that contains payment request
  final String requestedBy; // User ID who sent the payment request
  final String requestedByName;
  final double amount;
  final String? description;
  final List<String> targetUsers; // User IDs who need to pay (empty for direct chat)
  final Map<String, PaymentStatus> paymentStatuses; // userId -> status
  final DateTime createdAt;
  final bool isGroupPayment;
  final Map<String, dynamic>? metadata;

  PaymentRequestModel({
    required this.id,
    required this.chatId,
    required this.messageId,
    required this.requestedBy,
    required this.requestedByName,
    required this.amount,
    this.description,
    required this.targetUsers,
    required this.paymentStatuses,
    required this.createdAt,
    required this.isGroupPayment,
    this.metadata,
  });

  factory PaymentRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Parse payment statuses
    final statusesMap = data['paymentStatuses'] as Map<String, dynamic>? ?? {};
    final paymentStatuses = <String, PaymentStatus>{};
    statusesMap.forEach((key, value) {
      paymentStatuses[key] = PaymentStatus.values.firstWhere(
        (e) => e.toString() == value,
        orElse: () => PaymentStatus.pending,
      );
    });

    return PaymentRequestModel(
      id: doc.id,
      chatId: data['chatId'] ?? '',
      messageId: data['messageId'] ?? '',
      requestedBy: data['requestedBy'] ?? '',
      requestedByName: data['requestedByName'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      description: data['description']?.toString(),
      targetUsers: List<String>.from(data['targetUsers'] ?? []),
      paymentStatuses: paymentStatuses,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isGroupPayment: data['isGroupPayment'] ?? false,
      metadata: data['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'chatId': chatId,
      'messageId': messageId,
      'requestedBy': requestedBy,
      'requestedByName': requestedByName,
      'amount': amount,
      'description': description,
      'targetUsers': targetUsers,
      'paymentStatuses': paymentStatuses.map((key, value) => MapEntry(key, value.toString())),
      'createdAt': Timestamp.fromDate(createdAt),
      'isGroupPayment': isGroupPayment,
      'metadata': metadata,
    };
  }

  // Check if all users have paid
  bool isFullyPaid() {
    return paymentStatuses.values.every((status) => status == PaymentStatus.completed);
  }

  // Get users who haven't paid yet
  List<String> getPendingUsers() {
    return paymentStatuses.entries
        .where((entry) => entry.value == PaymentStatus.pending)
        .map((entry) => entry.key)
        .toList();
  }

  PaymentRequestModel copyWith({
    String? id,
    String? chatId,
    String? messageId,
    String? requestedBy,
    String? requestedByName,
    double? amount,
    String? description,
    List<String>? targetUsers,
    Map<String, PaymentStatus>? paymentStatuses,
    DateTime? createdAt,
    bool? isGroupPayment,
    Map<String, dynamic>? metadata,
  }) {
    return PaymentRequestModel(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      messageId: messageId ?? this.messageId,
      requestedBy: requestedBy ?? this.requestedBy,
      requestedByName: requestedByName ?? this.requestedByName,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      targetUsers: targetUsers ?? this.targetUsers,
      paymentStatuses: paymentStatuses ?? this.paymentStatuses,
      createdAt: createdAt ?? this.createdAt,
      isGroupPayment: isGroupPayment ?? this.isGroupPayment,
      metadata: metadata ?? this.metadata,
    );
  }
}

enum PaymentStatus {
  pending,
  initiated, // User clicked Pay Now
  completed, // Payment confirmed
  failed,
}

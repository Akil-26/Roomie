import 'package:cloud_firestore/cloud_firestore.dart';

enum ExpenseType { rent, utilities, groceries, cleaning, internet, other }

enum ExpenseStatus { pending, paid, cancelled }

class ExpenseModel {
  final String id;
  final String title;
  final String description;
  final double amount;
  final ExpenseType type;
  final ExpenseStatus status;
  final String groupId;
  final String createdBy;
  final String createdByName;
  final List<String> participants; // User IDs who need to pay
  final Map<String, double> splitAmounts; // userId -> amount they owe
  final Map<String, bool> paymentStatus; // userId -> has paid
  final DateTime createdAt;
  final DateTime? dueDate;
  final String? receiptUrl;
  final Map<String, dynamic>? metadata;

  ExpenseModel({
    required this.id,
    required this.title,
    required this.description,
    required this.amount,
    required this.type,
    required this.status,
    required this.groupId,
    required this.createdBy,
    required this.createdByName,
    required this.participants,
    required this.splitAmounts,
    required this.paymentStatus,
    required this.createdAt,
    this.dueDate,
    this.receiptUrl,
    this.metadata,
  });

  factory ExpenseModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ExpenseModel(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      type: ExpenseType.values.firstWhere(
        (e) => e.toString() == data['type'],
        orElse: () => ExpenseType.other,
      ),
      status: ExpenseStatus.values.firstWhere(
        (e) => e.toString() == data['status'],
        orElse: () => ExpenseStatus.pending,
      ),
      groupId: data['groupId'] ?? '',
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? '',
      participants: List<String>.from(data['participants'] ?? []),
      splitAmounts: Map<String, double>.from(
        (data['splitAmounts'] ?? {}).map((k, v) => MapEntry(k, v.toDouble())),
      ),
      paymentStatus: Map<String, bool>.from(data['paymentStatus'] ?? {}),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      dueDate:
          data['dueDate'] != null
              ? (data['dueDate'] as Timestamp).toDate()
              : null,
      receiptUrl: data['receiptUrl'],
      metadata: data['metadata'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'amount': amount,
      'type': type.toString(),
      'status': status.toString(),
      'groupId': groupId,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'participants': participants,
      'splitAmounts': splitAmounts,
      'paymentStatus': paymentStatus,
      'createdAt': Timestamp.fromDate(createdAt),
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'receiptUrl': receiptUrl,
      'metadata': metadata,
    };
  }

  // Helper methods
  double getTotalPaid() {
    return splitAmounts.entries
        .where((entry) => paymentStatus[entry.key] == true)
        .fold(0.0, (total, entry) => total + entry.value);
  }

  double getTotalPending() {
    return amount - getTotalPaid();
  }

  bool isFullyPaid() {
    return getTotalPending() <= 0.01; // Account for floating point precision
  }

  int getPaidParticipantsCount() {
    return paymentStatus.values.where((paid) => paid).length;
  }

  String getTypeDisplayName() {
    switch (type) {
      case ExpenseType.rent:
        return 'Rent';
      case ExpenseType.utilities:
        return 'Utilities';
      case ExpenseType.groceries:
        return 'Groceries';
      case ExpenseType.cleaning:
        return 'Cleaning';
      case ExpenseType.internet:
        return 'Internet';
      case ExpenseType.other:
        return 'Other';
    }
  }

  ExpenseModel copyWith({
    String? id,
    String? title,
    String? description,
    double? amount,
    ExpenseType? type,
    ExpenseStatus? status,
    String? groupId,
    String? createdBy,
    String? createdByName,
    List<String>? participants,
    Map<String, double>? splitAmounts,
    Map<String, bool>? paymentStatus,
    DateTime? createdAt,
    DateTime? dueDate,
    String? receiptUrl,
    Map<String, dynamic>? metadata,
  }) {
    return ExpenseModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      status: status ?? this.status,
      groupId: groupId ?? this.groupId,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      participants: participants ?? this.participants,
      splitAmounts: splitAmounts ?? this.splitAmounts,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      createdAt: createdAt ?? this.createdAt,
      dueDate: dueDate ?? this.dueDate,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      metadata: metadata ?? this.metadata,
    );
  }
}

// User balance summary
class UserBalance {
  final String userId;
  final String userName;
  final double totalOwed;
  final double totalPaid;
  final double netBalance; // positive = they owe you, negative = you owe them

  UserBalance({
    required this.userId,
    required this.userName,
    required this.totalOwed,
    required this.totalPaid,
    required this.netBalance,
  });
}

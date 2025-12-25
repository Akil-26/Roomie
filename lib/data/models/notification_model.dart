import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String type; // 'chat', 'expense', 'payment', 'group_join_conflict', etc.
  final Timestamp createdAt;
  final bool isRead;
  
  // Dynamic fields
  final String? senderName;
  final String? message;
  final String? title;
  final int? amount;
  final String? status;
  final Map<String, dynamic> data; // For extra data like groupId

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.createdAt,
    this.isRead = false,
    this.senderName,
    this.message,
    this.title,
    this.amount,
    this.status,
    this.data = const {},
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      type: data['type'] ?? '',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      isRead: data['isRead'] ?? false,
      senderName: data['senderName'],
      message: data['message'],
      title: data['title'],
      amount: data['amount'],
      status: data['status'],
      data: data['data'] is Map ? Map<String, dynamic>.from(data['data']) : {},
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'type': type,
      'createdAt': createdAt,
      'isRead': isRead,
      if (senderName != null) 'senderName': senderName,
      if (message != null) 'message': message,
      if (title != null) 'title': title,
      if (amount != null) 'amount': amount,
      if (status != null) 'status': status,
      'data': data,
    };
  }

  // Dynamic title generation based on type
  String getDynamicTitle() {
    switch (type) {
      case 'chat':
        return 'New message from ${senderName ?? "Someone"}';
      case 'expense':
        return 'New expense added';
      case 'payment':
        return 'Payment ${status ?? "updated"}';
      case 'group_join_conflict':
        return 'Join request conflict';
      case 'request_accepted':
        return 'Request accepted';
      default:
        return 'Notification';
    }
  }

  // Dynamic body generation based on type
  String getDynamicBody() {
    switch (type) {
      case 'chat':
        return message ?? '';
      case 'expense':
        return '${title ?? "Expense"} - ₹${amount ?? 0}';
      case 'payment':
        return 'Amount: ₹${amount ?? 0}';
      case 'group_join_conflict':
        return data['message'] ?? 'Please review the conflict';
      case 'request_accepted':
        return data['message'] ?? 'Your request was accepted';
      default:
        return '';
    }
  }

  // Helper getters for navigation IDs
  String? get chatId => data['chatId'];
  String? get expenseId => data['expenseId'];
  String? get groupId => data['groupId'];
  String? get paymentId => data['paymentId'];
}

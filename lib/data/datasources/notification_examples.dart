// This file shows examples of how to create notifications
// when different events happen in your app

import 'package:roomie/data/datasources/notification_service.dart';

/// Example 1: Create notification when a chat message is sent
/// Call this from your chat service after sending a message
Future<void> onChatMessageSent({
  required String receiverId,
  required String senderName,
  required String messageText,
  String? chatId,
}) async {
  final notificationService = NotificationService();
  
  await notificationService.createChatNotification(
    userId: receiverId,
    senderName: senderName,
    message: messageText,
    extraData: {
      if (chatId != null) 'chatId': chatId,
    },
  );
}

/// Example 2: Create notification when an expense is added
/// Call this from your expense service after creating an expense
Future<void> onExpenseCreated({
  required List<String> memberIds,
  required String expenseTitle,
  required int amount,
  String? groupId,
  String? expenseId,
}) async {
  final notificationService = NotificationService();
  
  // Create notification for each member
  for (final memberId in memberIds) {
    await notificationService.createExpenseNotification(
      userId: memberId,
      expenseTitle: expenseTitle,
      amount: amount,
      extraData: {
        if (groupId != null) 'groupId': groupId,
        if (expenseId != null) 'expenseId': expenseId,
      },
    );
  }
}

/// Example 3: Create notification when a payment status changes
/// Call this after a payment is processed
Future<void> onPaymentStatusChanged({
  required String userId,
  required String status, // 'SUCCESS', 'FAILED', 'PENDING'
  required int amount,
  String? paymentId,
  String? expenseId,
}) async {
  final notificationService = NotificationService();
  
  await notificationService.createPaymentNotification(
    userId: userId,
    status: status,
    amount: amount,
    extraData: {
      if (paymentId != null) 'paymentId': paymentId,
      if (expenseId != null) 'expenseId': expenseId,
    },
  );
}

// HOW TO INTEGRATE IN YOUR EXISTING CODE:
// 
// In your chat service (when sending a message):
// ----------------------------------------
// Future<void> sendMessage(String receiverId, String message) async {
//   // Your existing code to save message to Firestore
//   
//   // Add this line:
//   await onChatMessageSent(
//     receiverId: receiverId,
//     senderName: currentUser.name,
//     messageText: message,
//   );
// }
//
// In your expense service (when creating expense):
// ----------------------------------------
// Future<void> createExpense(String title, int amount, List<String> members) async {
//   // Your existing code to save expense to Firestore
//   
//   // Add this line:
//   await onExpenseCreated(
//     memberIds: members,
//     expenseTitle: title,
//     amount: amount,
//   );
// }
//
// In your payment service (after processing payment):
// ----------------------------------------
// Future<void> processPayment(String userId, int amount) async {
//   // Your existing payment processing code
//   
//   final status = paymentSuccessful ? 'SUCCESS' : 'FAILED';
//   
//   // Add this line:
//   await onPaymentStatusChanged(
//     userId: userId,
//     status: status,
//     amount: amount,
//   );
// }

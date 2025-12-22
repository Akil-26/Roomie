import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/models/payment_request_model.dart';

/// UPI payment result status
enum UpiPaymentResult {
  success,    // Payment completed
  cancelled,  // User cancelled
  failed,     // Payment failed
}

/// Service to handle UPI payment integration
class UpiPaymentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  static const String _paymentRequestsCollection = 'payment_requests';

  /// Open UPI payment app with pre-filled details
  /// [amount] - Amount to be paid
  /// [payeeName] - Name of the person requesting payment
  /// [payeePhoneNumber] - Phone number (stored as reference, not used as UPI ID)
  /// [payeeUpiId] - UPI ID of payee (format: username@bank) - REQUIRED for auto-fill
  /// [note] - Transaction note (defaults to "Roomie expence")
  /// 
  /// Returns UpiPaymentResult: success, cancelled, or failed
  Future<UpiPaymentResult> initiateUpiPayment({
    required double amount,
    required String payeeName,
    String? payeePhoneNumber,
    String? payeeUpiId,
    String? note,
  }) async {
    if (!Platform.isAndroid) {
      debugPrint('UPI payment is only supported on Android');
      return UpiPaymentResult.failed;
    }

    try {
      final transactionNote = note ?? 'Roomie expence';
      
      // 🔒 FIX: Only use payeeUpiId if it's a valid VPA (contains @)
      // Phone number alone is NOT a valid UPI ID
      String? validUpiId;
      if (payeeUpiId != null && payeeUpiId.contains('@')) {
        validUpiId = payeeUpiId;
      }
      // If no valid UPI ID, user will manually select recipient in UPI app
      
      print('🚀 Initiating UPI Payment');
      print('Amount: ₹$amount');
      print('Payee: $payeeName');
      print('Phone: ${payeePhoneNumber ?? "Not provided"}');
      print('Note: $transactionNote');
      print('UPI ID: ${validUpiId ?? "Not provided (user will select)"}');
      
      final upiUrl = _buildUpiUrl(
        payeeUpiId: validUpiId,
        payeeName: payeeName,
        amount: amount,
        note: transactionNote,
        phoneNumber: payeePhoneNumber,
      );
      
      print('UPI URL: $upiUrl');
      
      // Create UPI intent
      // Format: upi://pay?pa=UPI_ID&pn=NAME&am=AMOUNT&tn=NOTE&cu=INR
      final AndroidIntent intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: upiUrl,
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );

      print('Launching Android Intent...');
      await intent.launch();
      print('✅ Intent launched successfully');
      
      // Note: Android Intent doesn't return result automatically
      // User will be asked to confirm in payment_request_card
      // They can choose: YES (success), NO/Cancel (cancelled)
      return UpiPaymentResult.success;
    } catch (e) {
      debugPrint('❌ Error launching UPI payment: $e');
      return UpiPaymentResult.failed;
    }
  }

  /// Build UPI payment URL
  String _buildUpiUrl({
    String? payeeUpiId,
    required String payeeName,
    required double amount,
    required String note,
    String? phoneNumber,
  }) {
    // 🔒 FIX: Only include 'pa' param if valid UPI ID (contains @)
    // Without 'pa', UPI apps open with amount/note, user selects recipient
    final params = <String, String>{
      if (payeeUpiId != null && payeeUpiId.isNotEmpty && payeeUpiId.contains('@')) 
        'pa': payeeUpiId,
      'pn': payeeName,
      'am': amount.toStringAsFixed(2),
      'tn': note,
      'cu': 'INR', // Currency
      // mc (merchant code) only if phone number provided
      if (phoneNumber != null && phoneNumber.isNotEmpty) 'mc': phoneNumber,
    };

    final queryString = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return 'upi://pay?$queryString';
  }

  /// Create a payment request in Firestore
  Future<String> createPaymentRequest({
    required String chatId,
    required String messageId,
    required double amount,
    String? description,
    required List<String> targetUsers,
    required bool isGroupPayment,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Get current user's name
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final userName = userDoc.data()?['username'] ?? 
                      userDoc.data()?['name'] ?? 
                      currentUser.displayName ?? 
                      'Unknown';

      // Initialize payment statuses for all target users
      final paymentStatuses = <String, PaymentStatus>{};
      for (final userId in targetUsers) {
        paymentStatuses[userId] = PaymentStatus.pending;
      }

      final paymentRequest = PaymentRequestModel(
        id: '', // Will be set by Firestore
        chatId: chatId,
        messageId: messageId,
        requestedBy: currentUser.uid,
        requestedByName: userName,
        amount: amount,
        description: description,
        targetUsers: targetUsers,
        paymentStatuses: paymentStatuses,
        createdAt: DateTime.now(),
        isGroupPayment: isGroupPayment,
        metadata: metadata,
      );

      final docRef = await _firestore
          .collection(_paymentRequestsCollection)
          .add(paymentRequest.toFirestore());

      debugPrint('✅ Payment request created: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('❌ Error creating payment request: $e');
      rethrow;
    }
  }

  /// Update payment status
  Future<void> updatePaymentStatus({
    required String paymentRequestId,
    required String userId,
    required PaymentStatus status,
  }) async {
    try {
      await _firestore
          .collection(_paymentRequestsCollection)
          .doc(paymentRequestId)
          .update({
        'paymentStatuses.$userId': status.toString(),
      });

      debugPrint('✅ Updated payment status for $userId to $status');
    } catch (e) {
      debugPrint('❌ Error updating payment status: $e');
      rethrow;
    }
  }

  /// Get payment request by ID
  Future<PaymentRequestModel?> getPaymentRequest(String paymentRequestId) async {
    try {
      final doc = await _firestore
          .collection(_paymentRequestsCollection)
          .doc(paymentRequestId)
          .get();

      if (doc.exists) {
        return PaymentRequestModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting payment request: $e');
      return null;
    }
  }

  /// Get payment requests for a chat
  Stream<List<PaymentRequestModel>> getChatPaymentRequests(String chatId) {
    return _firestore
        .collection(_paymentRequestsCollection)
        .where('chatId', isEqualTo: chatId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => PaymentRequestModel.fromFirestore(doc)).toList());
  }

  /// Get payment requests where user needs to pay
  Stream<List<PaymentRequestModel>> getUserPaymentRequests(String userId) {
    return _firestore
        .collection(_paymentRequestsCollection)
        .where('targetUsers', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => PaymentRequestModel.fromFirestore(doc)).toList());
  }

  /// Delete payment request
  Future<void> deletePaymentRequest(String paymentRequestId) async {
    try {
      await _firestore
          .collection(_paymentRequestsCollection)
          .doc(paymentRequestId)
          .delete();
      debugPrint('✅ Deleted payment request: $paymentRequestId');
    } catch (e) {
      debugPrint('❌ Error deleting payment request: $e');
      rethrow;
    }
  }
}

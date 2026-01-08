import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/notification_service.dart';
import 'package:roomie/data/datasources/payments/razorpay_service.dart';
import 'package:roomie/data/models/payment_record_model.dart';
import 'package:roomie/core/logger.dart';

/// Singleton service for room payments.
/// 
/// CRITICAL RULES (DO NOT VIOLATE):
/// 1. Payments belong to OWNER SPACE only
/// 2. Private roommate space must NEVER see payments
/// 3. Payments are NOT linked to: room_members, private chat, expenses, groceries
/// 4. Roommates only see their OWN payment history
/// 5. Owner sees ALL payment records for the room
/// 6. NO payment automation, NO reminders, NO penalties
class RoomPaymentService {
  // Singleton pattern
  static final RoomPaymentService _instance = RoomPaymentService._internal();
  factory RoomPaymentService() => _instance;
  RoomPaymentService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();
  final RazorpayService _razorpayService = RazorpayService();

  static const String _paymentsCollection = 'room_payments';

  // ============================================================
  // PAYMENT CREATION & PROCESSING
  // ============================================================

  /// Create a pending payment record (before Razorpay checkout)
  /// Returns the payment ID for tracking
  Future<String?> createPendingPayment({
    required String roomId,
    required String ownerId,
    required double amount,
    required String currency,
    required PaymentPurpose purpose,
    String? note,
  }) async {
    final user = _authService.currentUser;
    if (user == null) {
      AppLogger.e('❌ Not authenticated');
      return null;
    }

    try {
      final docRef = _firestore.collection(_paymentsCollection).doc();
      
      final payment = PaymentRecordModel(
        paymentId: docRef.id,
        roomId: roomId,
        ownerId: ownerId,
        payerId: user.uid,
        amount: amount,
        currency: currency,
        purpose: purpose,
        status: PaymentStatus.pending,
        createdAt: DateTime.now(),
        note: note,
      );

      await docRef.set(payment.toMap());
      AppLogger.d('✅ Pending payment created: ${docRef.id}');
      
      return docRef.id;
    } catch (e) {
      AppLogger.e('❌ Error creating pending payment: $e');
      return null;
    }
  }

  /// Mark payment as successful (after Razorpay success)
  Future<bool> markPaymentSuccess({
    required String paymentId,
    required String razorpayPaymentId,
    String? razorpayOrderId,
  }) async {
    try {
      await _firestore.collection(_paymentsCollection).doc(paymentId).update({
        'status': PaymentStatus.success.value,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpayOrderId': razorpayOrderId,
        'completedAt': FieldValue.serverTimestamp(),
      });
      
      AppLogger.d('✅ Payment marked as success: $paymentId');
      return true;
    } catch (e) {
      AppLogger.e('❌ Error marking payment success: $e');
      return false;
    }
  }

  /// Mark payment as failed (after Razorpay failure)
  Future<bool> markPaymentFailed({
    required String paymentId,
    String? errorCode,
    String? errorMessage,
  }) async {
    try {
      await _firestore.collection(_paymentsCollection).doc(paymentId).update({
        'status': PaymentStatus.failed.value,
        'errorCode': errorCode,
        'errorMessage': errorMessage,
        'completedAt': FieldValue.serverTimestamp(),
      });
      
      AppLogger.d('✅ Payment marked as failed: $paymentId');
      return true;
    } catch (e) {
      AppLogger.e('❌ Error marking payment failed: $e');
      return false;
    }
  }

  /// Complete payment flow with Stripe
  /// 1. Creates pending payment record
  /// 2. Creates Stripe payment
  /// 3. Updates payment status based on result
  /// 4. Sends notifications
  Future<PaymentRecordModel?> processPayment({
    required String roomId,
    required String roomName,
    required String ownerId,
    required String ownerName,
    required double amount,
    required String currency,
    required PaymentPurpose purpose,
    String? note,
    required Function(bool success, String? message) onComplete,
  }) async {
    final user = _authService.currentUser;
    if (user == null) {
      onComplete(false, 'Not authenticated');
      return null;
    }

    // 1. Create pending payment record
    final paymentId = await createPendingPayment(
      roomId: roomId,
      ownerId: ownerId,
      amount: amount,
      currency: currency,
      purpose: purpose,
      note: note,
    );

    if (paymentId == null) {
      onComplete(false, 'Failed to create payment record');
      return null;
    }

    try {
      // 2. Start Razorpay payment (UPI + Cards + Wallets)
      _razorpayService.startPayment(
        amount: amount,
        recipientName: ownerName,
        recipientId: ownerId,
        note: note ?? '${purpose.displayName} payment for $roomName',
        messageId: paymentId,
        onComplete: (result) async {
          if (result.success && result.paymentId != null) {
            // 3a. Payment successful
            final updated = await markPaymentSuccess(
              paymentId: paymentId,
              razorpayPaymentId: result.paymentId!,
              razorpayOrderId: result.orderId,
            );

            if (updated) {
              // 4. Send notifications
              await _sendPaymentSuccessNotifications(
                roomId: roomId,
                roomName: roomName,
                ownerId: ownerId,
                payerId: user.uid,
                amount: amount,
                currency: currency,
                purpose: purpose,
              );
              
              onComplete(true, 'Payment successful');
            } else {
              onComplete(false, 'Payment succeeded but failed to save record');
            }
          } else if (result.errorCode == 'CANCELLED') {
            // User cancelled
            onComplete(false, 'Payment cancelled');
          } else {
            // 3b. Payment failed
            await markPaymentFailed(
              paymentId: paymentId,
              errorMessage: result.errorMessage ?? 'Payment failed',
            );
            onComplete(false, result.errorMessage ?? 'Payment failed');
          }
        },
      );
    } catch (e) {
      AppLogger.e('❌ Payment processing error: $e');
      await markPaymentFailed(
        paymentId: paymentId,
        errorMessage: e.toString(),
      );
      onComplete(false, 'Payment error: $e');
    }

    // Return null here since the actual result comes through callback
    return null;
  }

  // ============================================================
  // PAYMENT HISTORY - VISIBILITY RULES
  // ============================================================

  /// Get payment history for current user (roommate view)
  /// RULE: Roommates only see their OWN payments
  Future<List<PaymentRecordModel>> getMyPaymentHistory(String roomId) async {
    final user = _authService.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _firestore
          .collection(_paymentsCollection)
          .where('roomId', isEqualTo: roomId)
          .where('payerId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => PaymentRecordModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      AppLogger.e('❌ Error getting my payment history: $e');
      return [];
    }
  }

  /// Get all payment records for a room (owner view)
  /// RULE: Only owner can see all payments
  Future<List<PaymentRecordModel>> getRoomPayments(String roomId) async {
    final user = _authService.currentUser;
    if (user == null) return [];

    try {
      // First verify user is the owner
      final roomDoc = await _firestore.collection('groups').doc(roomId).get();
      if (!roomDoc.exists) return [];
      
      final roomData = roomDoc.data()!;
      final ownerId = roomData['ownerId'];
      
      if (ownerId != user.uid) {
        AppLogger.e('❌ Only room owner can view all payments');
        return [];
      }

      final snapshot = await _firestore
          .collection(_paymentsCollection)
          .where('roomId', isEqualTo: roomId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => PaymentRecordModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      AppLogger.e('❌ Error getting room payments: $e');
      return [];
    }
  }

  /// Stream payment history for current user (real-time updates)
  Stream<List<PaymentRecordModel>> streamMyPaymentHistory(String roomId) {
    final user = _authService.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection(_paymentsCollection)
        .where('roomId', isEqualTo: roomId)
        .where('payerId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PaymentRecordModel.fromFirestore(doc))
            .toList());
  }

  /// Stream all room payments (owner view, real-time)
  Stream<List<PaymentRecordModel>> streamRoomPayments(String roomId, String ownerId) {
    final user = _authService.currentUser;
    if (user == null || user.uid != ownerId) {
      return Stream.value([]);
    }

    return _firestore
        .collection(_paymentsCollection)
        .where('roomId', isEqualTo: roomId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PaymentRecordModel.fromFirestore(doc))
            .toList());
  }

  // ============================================================
  // PAYMENT STATS (OWNER ONLY)
  // ============================================================

  /// Get payment summary for owner (who paid / who didn't this month)
  Future<Map<String, dynamic>> getRoomPaymentSummary(String roomId) async {
    final user = _authService.currentUser;
    if (user == null) return {};

    try {
      // Verify user is owner
      final roomDoc = await _firestore.collection('groups').doc(roomId).get();
      if (!roomDoc.exists) return {};
      
      final roomData = roomDoc.data()!;
      if (roomData['ownerId'] != user.uid) {
        return {};
      }

      // Get this month's payments
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      
      final snapshot = await _firestore
          .collection(_paymentsCollection)
          .where('roomId', isEqualTo: roomId)
          .where('status', isEqualTo: PaymentStatus.success.value)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .get();

      final payments = snapshot.docs
          .map((doc) => PaymentRecordModel.fromFirestore(doc))
          .toList();

      // Calculate totals
      double totalCollected = 0;
      Set<String> paidUserIds = {};
      
      for (final payment in payments) {
        totalCollected += payment.amount;
        paidUserIds.add(payment.payerId);
      }

      return {
        'totalCollected': totalCollected,
        'paymentCount': payments.length,
        'paidUserIds': paidUserIds.toList(),
        'currency': roomData['rentCurrency'] ?? 'INR',
        'monthYear': '${now.month}/${now.year}',
      };
    } catch (e) {
      AppLogger.e('❌ Error getting payment summary: $e');
      return {};
    }
  }

  // ============================================================
  // NOTIFICATIONS
  // ============================================================

  Future<void> _sendPaymentSuccessNotifications({
    required String roomId,
    required String roomName,
    required String ownerId,
    required String payerId,
    required double amount,
    required String currency,
    required PaymentPurpose purpose,
  }) async {
    final symbol = _getCurrencySymbol(currency);
    final formattedAmount = '$symbol${amount.toStringAsFixed(2)}';

    // Notify owner
    await _notificationService.sendUserNotification(
      userId: ownerId,
      title: 'Payment Received',
      body: 'You received $formattedAmount for ${purpose.displayName.toLowerCase()} in "$roomName"',
      type: 'payment_received',
      data: {
        'roomId': roomId,
        'roomName': roomName,
        'payerId': payerId,
        'amount': amount,
        'currency': currency,
        'purpose': purpose.value,
      },
    );

    // Notify payer (confirmation)
    await _notificationService.sendUserNotification(
      userId: payerId,
      title: 'Payment Successful',
      body: 'Your $formattedAmount ${purpose.displayName.toLowerCase()} payment for "$roomName" was successful',
      type: 'payment_success',
      data: {
        'roomId': roomId,
        'roomName': roomName,
        'amount': amount,
        'currency': currency,
        'purpose': purpose.value,
      },
    );
  }

  Future<void> _sendPaymentFailureNotification({
    required String payerId,
    required String roomName,
    required double amount,
    required String currency,
    String? errorMessage,
  }) async {
    final symbol = _getCurrencySymbol(currency);
    final formattedAmount = '$symbol${amount.toStringAsFixed(2)}';

    await _notificationService.sendUserNotification(
      userId: payerId,
      title: 'Payment Failed',
      body: 'Your $formattedAmount payment for "$roomName" failed. ${errorMessage ?? 'Please try again.'}',
      type: 'payment_failed',
      data: {
        'roomName': roomName,
        'amount': amount,
        'currency': currency,
        'errorMessage': errorMessage,
      },
    );
  }

  String _getCurrencySymbol(String currency) {
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

  // ============================================================
  // UTILITY METHODS
  // ============================================================

  /// Check if current user can make payments in this room
  /// (room must have an approved owner)
  Future<bool> canMakePayment(String roomId) async {
    try {
      final roomDoc = await _firestore.collection('groups').doc(roomId).get();
      if (!roomDoc.exists) return false;
      
      final roomData = roomDoc.data()!;
      final ownerId = roomData['ownerId'];
      
      // Room must have an owner for payments
      return ownerId != null && ownerId.toString().isNotEmpty;
    } catch (e) {
      AppLogger.e('❌ Error checking payment eligibility: $e');
      return false;
    }
  }

  /// Get room owner details for payment
  Future<Map<String, dynamic>?> getRoomOwnerDetails(String roomId) async {
    try {
      final roomDoc = await _firestore.collection('groups').doc(roomId).get();
      if (!roomDoc.exists) return null;
      
      final roomData = roomDoc.data()!;
      final ownerId = roomData['ownerId'];
      
      if (ownerId == null) return null;

      final ownerDoc = await _firestore.collection('users').doc(ownerId).get();
      if (!ownerDoc.exists) return null;

      final ownerData = ownerDoc.data()!;
      return {
        'ownerId': ownerId,
        'ownerName': ownerData['username'] ?? ownerData['name'] ?? 'Owner',
        'ownerEmail': ownerData['email'],
        'roomName': roomData['name'],
        'rentAmount': roomData['rentAmount'],
        'rentCurrency': roomData['rentCurrency'] ?? 'INR',
      };
    } catch (e) {
      AppLogger.e('❌ Error getting room owner details: $e');
      return null;
    }
  }

  /// Check if current user is the room owner
  Future<bool> isRoomOwner(String roomId) async {
    final user = _authService.currentUser;
    if (user == null) return false;

    try {
      final roomDoc = await _firestore.collection('groups').doc(roomId).get();
      if (!roomDoc.exists) return false;
      
      return roomDoc.data()?['ownerId'] == user.uid;
    } catch (e) {
      return false;
    }
  }
}

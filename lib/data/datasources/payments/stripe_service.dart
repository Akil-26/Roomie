// =================================================================
// FROZEN STRIPE SERVICE - NOT IN USE
// =================================================================
// Stripe does NOT support UPI payments. Using Razorpay instead.
// This file is kept for reference and potential future use.
// =================================================================

// ignore_for_file: depend_on_referenced_packages, uri_does_not_exist, undefined_identifier, undefined_method, creation_with_non_type, non_type_in_catch_clause

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/payments/payment_service.dart';
import 'package:roomie/core/logger.dart';

/// Stripe payment service implementation.
/// 
/// ONLY this file talks to Stripe SDK.
/// All other parts of the app use the PaymentGateway interface.
/// 
/// TEST MODE RULES (CRITICAL):
/// - Use sk_test_xxx and pk_test_xxx keys ONLY
/// - Test card: 4242 4242 4242 4242
/// - NEVER use live keys in development
class StripeService implements PaymentGateway {
  static final StripeService _instance = StripeService._internal();
  factory StripeService() => _instance;
  StripeService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  bool _isInitialized = false;

  // Stripe keys from environment
  static String get _publishableKey => 
      dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '';
  static String get _secretKey => 
      dotenv.env['STRIPE_SECRET_KEY'] ?? '';

  // Merchant info (reserved for future use in payment sheet configuration)
  static const String _merchantDisplayName = 'Roomie';
  // ignore: unused_field
  static const String _merchantCountryCode = 'IN';
  // ignore: unused_field
  static const String _defaultCurrency = 'INR';

  @override
  String get gatewayId => 'stripe';

  @override
  bool get isTestMode => _publishableKey.startsWith('pk_test_');

  /// Initialize Stripe SDK
  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (_publishableKey.isEmpty) {
      AppLogger.e('❌ Stripe publishable key not found in environment');
      return;
    }

    try {
      Stripe.publishableKey = _publishableKey;
      Stripe.merchantIdentifier = 'merchant.com.roomie.app';
      
      await Stripe.instance.applySettings();
      
      _isInitialized = true;
      AppLogger.d('✅ Stripe initialized (Test Mode: $isTestMode)');
    } catch (e) {
      AppLogger.e('❌ Stripe initialization error: $e');
    }
  }

  @override
  void dispose() {
    _isInitialized = false;
    AppLogger.d('🔄 Stripe service disposed');
  }

  /// Create a PaymentIntent
  /// 
  /// NOTE: In production, this should call your backend server to create
  /// the PaymentIntent. For test mode, we'll create it via Firestore function.
  @override
  Future<PaymentResult> createPayment({
    required double amount,
    required String currency,
    required PaymentMetadata metadata,
  }) async {
    try {
      // Convert amount to smallest currency unit (paise for INR, cents for USD)
      final amountInSmallestUnit = (amount * 100).toInt();

      // For production: Call your backend API to create PaymentIntent
      // For test mode: We'll use a Cloud Function or create directly
      
      // Create a payment record in Firestore to track this payment
      final paymentRef = _firestore.collection('stripe_payments').doc();
      
      await paymentRef.set({
        'amount': amountInSmallestUnit,
        'currency': currency.toLowerCase(),
        'metadata': metadata.toMap(),
        'status': 'pending',
        'gateway': gatewayId,
        'createdAt': FieldValue.serverTimestamp(),
        'userId': _authService.currentUser?.uid,
      });

      // NOTE: In real implementation, your backend creates the PaymentIntent
      // and returns the client_secret. For now, we'll simulate this.
      
      // For demo purposes, we return the payment ID
      // The actual client_secret would come from your backend
      return PaymentResult.success(
        paymentId: paymentRef.id,
        metadata: {'firestore_id': paymentRef.id},
      );
    } catch (e) {
      AppLogger.e('❌ Error creating Stripe payment: $e');
      return PaymentResult.failure(
        errorCode: 'CREATE_ERROR',
        errorMessage: e.toString(),
      );
    }
  }

  /// Present the Stripe payment sheet
  /// 
  /// [clientSecret] - The client_secret from PaymentIntent
  /// [amount] - Display amount
  /// [recipientName] - Who is receiving the payment
  Future<PaymentResult> presentPaymentSheet({
    required String clientSecret,
    required double amount,
    required String recipientName,
    String currency = 'INR',
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Initialize the payment sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: _merchantDisplayName,
          style: ThemeMode.system,
          appearance: const PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: Color(0xFF6366F1), // Stripe purple
            ),
          ),
          billingDetails: BillingDetails(
            email: _authService.currentUser?.email,
          ),
        ),
      );

      // Present the payment sheet
      await Stripe.instance.presentPaymentSheet();

      AppLogger.d('✅ Stripe payment successful');
      
      return PaymentResult.success(
        paymentId: 'confirmed', // Will be updated with actual ID
        metadata: {'status': 'succeeded'},
      );
    } on StripeException catch (e) {
      AppLogger.e('❌ Stripe payment error: ${e.error.localizedMessage}');
      
      if (e.error.code == FailureCode.Canceled) {
        return PaymentResult.cancelled();
      }
      
      return PaymentResult.failure(
        errorCode: e.error.code.toString(),
        errorMessage: e.error.localizedMessage ?? 'Payment failed',
      );
    } catch (e) {
      AppLogger.e('❌ Unexpected payment error: $e');
      return PaymentResult.failure(
        errorCode: 'UNKNOWN',
        errorMessage: e.toString(),
      );
    }
  }

  /// Present card payment form
  /// 
  /// This is an alternative to PaymentSheet for more control
  Future<PaymentResult> presentCardPayment({
    required String clientSecret,
    required double amount,
    required String recipientName,
    String currency = 'INR',
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Confirm the payment with card details
      final paymentIntent = await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: clientSecret,
        data: const PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );

      if (paymentIntent.status == PaymentIntentsStatus.Succeeded) {
        AppLogger.d('✅ Card payment successful: ${paymentIntent.id}');
        return PaymentResult.success(
          paymentId: paymentIntent.id,
          metadata: {'status': paymentIntent.status.name},
        );
      } else if (paymentIntent.status == PaymentIntentsStatus.RequiresAction) {
        // 3D Secure authentication required
        return PaymentResult.requiresAction(
          paymentId: paymentIntent.id,
          clientSecret: clientSecret,
        );
      } else {
        return PaymentResult.failure(
          errorCode: 'STATUS_${paymentIntent.status.name}',
          errorMessage: 'Payment not completed',
        );
      }
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        return PaymentResult.cancelled();
      }
      return PaymentResult.failure(
        errorCode: e.error.code.toString(),
        errorMessage: e.error.localizedMessage ?? 'Payment failed',
      );
    } catch (e) {
      return PaymentResult.failure(
        errorCode: 'UNKNOWN',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<bool> verifyPayment({
    required String paymentId,
    Map<String, dynamic>? paymentData,
  }) async {
    try {
      // In production, verify with your backend
      // The backend should check with Stripe API that payment succeeded
      
      final doc = await _firestore
          .collection('stripe_payments')
          .doc(paymentId)
          .get();
      
      if (!doc.exists) {
        AppLogger.e('❌ Payment record not found: $paymentId');
        return false;
      }

      final status = doc.data()?['status'];
      return status == 'succeeded' || status == 'success';
    } catch (e) {
      AppLogger.e('❌ Error verifying payment: $e');
      return false;
    }
  }

  @override
  Future<String> getPaymentStatus(String paymentId) async {
    try {
      final doc = await _firestore
          .collection('stripe_payments')
          .doc(paymentId)
          .get();
      
      return doc.data()?['status'] ?? 'unknown';
    } catch (e) {
      AppLogger.e('❌ Error getting payment status: $e');
      return 'error';
    }
  }

  /// Update payment status in Firestore
  Future<void> updatePaymentStatus({
    required String paymentId,
    required String status,
    String? stripePaymentIntentId,
    String? errorMessage,
  }) async {
    try {
      await _firestore.collection('stripe_payments').doc(paymentId).update({
        'status': status,
        'stripePaymentIntentId': stripePaymentIntentId,
        'errorMessage': errorMessage,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      AppLogger.e('❌ Error updating payment status: $e');
    }
  }

  /// Save payment to history (for both sender and recipient)
  Future<void> savePaymentHistory({
    required String odId,
    required String odName,
    required String recipientId,
    required String recipientName,
    required double amount,
    required String paymentId,
    String? stripePaymentIntentId,
    String? note,
    String? chatId,
    String? messageId,
    String? roomId,
    String paymentType = 'general',
  }) async {
    final historyId = '${paymentId}_${DateTime.now().millisecondsSinceEpoch}';
    
    final record = PaymentHistoryRecord(
      id: historyId,
      odId: odId,
      odName: odName,
      recipientId: recipientId,
      recipientName: recipientName,
      amount: amount,
      note: note,
      gatewayPaymentId: stripePaymentIntentId ?? paymentId,
      gateway: gatewayId,
      status: 'success',
      chatId: chatId,
      messageId: messageId,
      roomId: roomId,
      paymentType: paymentType,
      createdAt: DateTime.now(),
    );

    try {
      // Save to sender's payment history
      await _firestore
          .collection('users')
          .doc(odId)
          .collection('payment_history')
          .doc(historyId)
          .set({
            ...record.toMap(),
            'type': 'sent',
          });

      // Save to recipient's payment history
      await _firestore
          .collection('users')
          .doc(recipientId)
          .collection('payment_history')
          .doc(historyId)
          .set({
            ...record.toMap(),
            'type': 'received',
          });

      // Save to global payments collection
      await _firestore
          .collection('payments')
          .doc(historyId)
          .set(record.toMap());

      AppLogger.d('✅ Payment history saved: $historyId');
    } catch (e) {
      AppLogger.e('❌ Error saving payment history: $e');
    }
  }

  /// Get payment history for current user
  Stream<List<PaymentHistoryRecord>> getPaymentHistory({String? type}) {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      return Stream.value([]);
    }

    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(userId)
        .collection('payment_history')
        .where('gateway', isEqualTo: gatewayId)
        .orderBy('createdAt', descending: true);

    if (type != null) {
      query = query.where('type', isEqualTo: type);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => PaymentHistoryRecord.fromMap(doc.data()))
          .toList();
    });
  }
}

// Export the singleton instance for easy access
final stripeService = StripeService();

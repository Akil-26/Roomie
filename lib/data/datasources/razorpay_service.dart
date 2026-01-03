import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/core/logger.dart';

/// Razorpay payment result model
class RazorpayPaymentResult {
  final bool success;
  final String? paymentId;
  final String? orderId;
  final String? signature;
  final String? errorCode;
  final String? errorMessage;

  const RazorpayPaymentResult({
    required this.success,
    this.paymentId,
    this.orderId,
    this.signature,
    this.errorCode,
    this.errorMessage,
  });

  factory RazorpayPaymentResult.success({
    required String paymentId,
    String? orderId,
    String? signature,
  }) {
    return RazorpayPaymentResult(
      success: true,
      paymentId: paymentId,
      orderId: orderId,
      signature: signature,
    );
  }

  factory RazorpayPaymentResult.failure({
    required String errorCode,
    required String errorMessage,
  }) {
    return RazorpayPaymentResult(
      success: false,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  factory RazorpayPaymentResult.cancelled() {
    return const RazorpayPaymentResult(
      success: false,
      errorCode: 'CANCELLED',
      errorMessage: 'Payment was cancelled by user',
    );
  }
}

/// Payment history model for storing in Firestore
class PaymentHistory {
  final String id;
  final String odId;
  final String odName;
  final String recipientId;
  final String recipientName;
  final double amount;
  final String currency;
  final String? note;
  final String paymentId;
  final String? orderId;
  final String status;
  final String paymentMethod;
  final String? chatId;
  final String? messageId;
  final DateTime createdAt;

  const PaymentHistory({
    required this.id,
    required this.odId,
    required this.odName,
    required this.recipientId,
    required this.recipientName,
    required this.amount,
    this.currency = 'INR',
    this.note,
    required this.paymentId,
    this.orderId,
    required this.status,
    this.paymentMethod = 'razorpay',
    this.chatId,
    this.messageId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': odId,
      'userName': odName,
      'recipientId': recipientId,
      'recipientName': recipientName,
      'amount': amount,
      'currency': currency,
      'note': note,
      'paymentId': paymentId,
      'orderId': orderId,
      'status': status,
      'paymentMethod': paymentMethod,
      'chatId': chatId,
      'messageId': messageId,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory PaymentHistory.fromMap(Map<String, dynamic> map) {
    return PaymentHistory(
      id: map['id'] ?? '',
      odId: map['userId'] ?? '',
      odName: map['userName'] ?? '',
      recipientId: map['recipientId'] ?? '',
      recipientName: map['recipientName'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency'] ?? 'INR',
      note: map['note'],
      paymentId: map['paymentId'] ?? '',
      orderId: map['orderId'],
      status: map['status'] ?? 'unknown',
      paymentMethod: map['paymentMethod'] ?? 'razorpay',
      chatId: map['chatId'],
      messageId: map['messageId'],
      createdAt: map['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : DateTime.now(),
    );
  }
}

/// Singleton service for Razorpay payment integration
class RazorpayService {
  static final RazorpayService _instance = RazorpayService._internal();
  factory RazorpayService() => _instance;
  RazorpayService._internal();

  Razorpay? _razorpay;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  // Callbacks for payment events
  Function(RazorpayPaymentResult)? _onPaymentComplete;

  // Razorpay API Key (Test mode - replace with live key for production)
  // IMPORTANT: Store this securely in environment variables for production
  static const String _testApiKey = 'rzp_test_YOUR_KEY_HERE'; // Replace with your test key
  static const String _liveApiKey = 'rzp_live_YOUR_KEY_HERE'; // Replace with your live key
  
  // Set to true for production
  static const bool _isProduction = false;
  
  String get _apiKey => _isProduction ? _liveApiKey : _testApiKey;

  /// Initialize Razorpay instance
  void initialize() {
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    
    AppLogger.d('✅ Razorpay initialized');
  }

  /// Dispose Razorpay instance
  void dispose() {
    _razorpay?.clear();
    _razorpay = null;
    AppLogger.d('🔄 Razorpay disposed');
  }

  /// Open Razorpay payment checkout
  /// 
  /// [amount] - Amount in INR (will be converted to paise)
  /// [recipientName] - Name of the person receiving payment
  /// [note] - Payment description/note
  /// [chatId] - Optional chat ID for reference
  /// [messageId] - Optional message ID for reference
  /// [recipientId] - ID of the recipient user
  Future<RazorpayPaymentResult> openPayment({
    required double amount,
    required String recipientName,
    required String recipientId,
    String? note,
    String? chatId,
    String? messageId,
    String? prefillEmail,
    String? prefillPhone,
  }) async {
    if (_razorpay == null) {
      initialize();
    }

    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      return RazorpayPaymentResult.failure(
        errorCode: 'AUTH_ERROR',
        errorMessage: 'User not authenticated',
      );
    }

    // Get current user details from Firestore
    String userName = currentUser.displayName ?? 'User';
    String userEmail = currentUser.email ?? '';
    String userPhone = '';

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        userName = userData['username'] ?? userData['name'] ?? userName;
        userEmail = userData['email'] ?? userEmail;
        userPhone = userData['phone'] ?? '';
      }
    } catch (e) {
      AppLogger.e('Error fetching user details: $e');
    }

    // Convert amount to paise (Razorpay uses smallest currency unit)
    final amountInPaise = (amount * 100).toInt();

    // Note: In production, generate order_id from your server using Razorpay Orders API
    // final orderId = 'order_${DateTime.now().millisecondsSinceEpoch}';

    final options = {
      'key': _apiKey,
      'amount': amountInPaise,
      'currency': 'INR',
      'name': 'Roomie',
      'description': note ?? 'Payment to $recipientName',
      'order_id': '', // Leave empty for client-side only (use server-generated order_id in production)
      'prefill': {
        'name': userName,
        'email': prefillEmail ?? userEmail,
        'contact': prefillPhone ?? userPhone,
      },
      'notes': {
        'chat_id': chatId ?? '',
        'message_id': messageId ?? '',
        'recipient_id': recipientId,
        'recipient_name': recipientName,
        'sender_id': currentUser.uid,
        'sender_name': userName,
      },
      'theme': {
        'color': '#1976D2', // Primary blue color
      },
      'modal': {
        'confirm_close': true,
        'animation': true,
      },
      'retry': {
        'enabled': true,
        'max_count': 3,
      },
    };

    // Create a completer to wait for payment result
    final completer = Future<RazorpayPaymentResult>.delayed(
      Duration.zero,
      () async {
        RazorpayPaymentResult? result;
        
        _onPaymentComplete = (paymentResult) {
          result = paymentResult;
        };

        try {
          _razorpay!.open(options);
          
          // Wait for payment to complete (with timeout)
          await Future.delayed(const Duration(minutes: 10), () {
            result ??= RazorpayPaymentResult.cancelled();
          });
          
          return result ?? RazorpayPaymentResult.cancelled();
        } catch (e) {
          AppLogger.e('Razorpay open error: $e');
          return RazorpayPaymentResult.failure(
            errorCode: 'OPEN_ERROR',
            errorMessage: e.toString(),
          );
        }
      },
    );

    return completer;
  }

  /// Start payment flow with callback
  void startPayment({
    required double amount,
    required String recipientName,
    required String recipientId,
    String? note,
    String? chatId,
    String? messageId,
    String? prefillEmail,
    String? prefillPhone,
    required Function(RazorpayPaymentResult) onComplete,
  }) {
    if (_razorpay == null) {
      initialize();
    }

    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      onComplete(RazorpayPaymentResult.failure(
        errorCode: 'AUTH_ERROR',
        errorMessage: 'User not authenticated',
      ));
      return;
    }

    _onPaymentComplete = onComplete;

    // Fetch user details and open payment
    _fetchUserAndOpenPayment(
      currentUser: currentUser,
      amount: amount,
      recipientName: recipientName,
      recipientId: recipientId,
      note: note,
      chatId: chatId,
      messageId: messageId,
      prefillEmail: prefillEmail,
      prefillPhone: prefillPhone,
    );
  }

  Future<void> _fetchUserAndOpenPayment({
    required dynamic currentUser,
    required double amount,
    required String recipientName,
    required String recipientId,
    String? note,
    String? chatId,
    String? messageId,
    String? prefillEmail,
    String? prefillPhone,
  }) async {
    String userName = currentUser.displayName ?? 'User';
    String userEmail = currentUser.email ?? '';
    String userPhone = '';

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        userName = userData['username'] ?? userData['name'] ?? userName;
        userEmail = userData['email'] ?? userEmail;
        userPhone = userData['phone'] ?? '';
      }
    } catch (e) {
      AppLogger.e('Error fetching user details: $e');
    }

    // Convert amount to paise
    final amountInPaise = (amount * 100).toInt();

    final options = {
      'key': _apiKey,
      'amount': amountInPaise,
      'currency': 'INR',
      'name': 'Roomie',
      'description': note ?? 'Payment to $recipientName',
      'prefill': {
        'name': userName,
        'email': prefillEmail ?? userEmail,
        'contact': prefillPhone ?? userPhone,
      },
      'notes': {
        'chat_id': chatId ?? '',
        'message_id': messageId ?? '',
        'recipient_id': recipientId,
        'recipient_name': recipientName,
        'sender_id': currentUser.uid,
        'sender_name': userName,
      },
      'theme': {
        'color': '#1976D2',
      },
      'retry': {
        'enabled': true,
        'max_count': 3,
      },
    };

    try {
      _razorpay!.open(options);
    } catch (e) {
      AppLogger.e('Razorpay open error: $e');
      _onPaymentComplete?.call(RazorpayPaymentResult.failure(
        errorCode: 'OPEN_ERROR',
        errorMessage: e.toString(),
      ));
    }
  }

  /// Handle successful payment
  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    AppLogger.d('✅ Razorpay Payment Success: ${response.paymentId}');
    
    final result = RazorpayPaymentResult.success(
      paymentId: response.paymentId ?? '',
      orderId: response.orderId,
      signature: response.signature,
    );
    
    _onPaymentComplete?.call(result);
  }

  /// Handle payment error
  void _handlePaymentError(PaymentFailureResponse response) {
    AppLogger.e('❌ Razorpay Payment Error: ${response.code} - ${response.message}');
    
    final result = RazorpayPaymentResult.failure(
      errorCode: response.code?.toString() ?? 'UNKNOWN',
      errorMessage: response.message ?? 'Payment failed',
    );
    
    _onPaymentComplete?.call(result);
  }

  /// Handle external wallet selection
  void _handleExternalWallet(ExternalWalletResponse response) {
    AppLogger.d('📱 External Wallet Selected: ${response.walletName}');
    // External wallet handling - payment continues in wallet app
  }

  /// Save payment to history (both sender and recipient)
  Future<void> savePaymentHistory({
    required String odId,
    required String odName,
    required String recipientId,
    required String recipientName,
    required double amount,
    required String paymentId,
    String? orderId,
    String? note,
    String? chatId,
    String? messageId,
  }) async {
    final historyId = '${paymentId}_${DateTime.now().millisecondsSinceEpoch}';
    
    final payment = PaymentHistory(
      id: historyId,
      odId: odId,
      odName: odName,
      recipientId: recipientId,
      recipientName: recipientName,
      amount: amount,
      note: note,
      paymentId: paymentId,
      orderId: orderId,
      status: 'success',
      chatId: chatId,
      messageId: messageId,
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
            ...payment.toMap(),
            'type': 'sent',
          });

      // Save to recipient's payment history
      await _firestore
          .collection('users')
          .doc(recipientId)
          .collection('payment_history')
          .doc(historyId)
          .set({
            ...payment.toMap(),
            'type': 'received',
          });

      // Also save to global payments collection for admin tracking
      await _firestore
          .collection('payments')
          .doc(historyId)
          .set(payment.toMap());

      AppLogger.d('✅ Payment history saved: $historyId');
    } catch (e) {
      AppLogger.e('❌ Error saving payment history: $e');
    }
  }

  /// Get payment history for current user
  Stream<List<PaymentHistory>> getPaymentHistory({String? type}) {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      return Stream.value([]);
    }

    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(userId)
        .collection('payment_history')
        .orderBy('createdAt', descending: true);

    if (type != null) {
      query = query.where('type', isEqualTo: type);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => PaymentHistory.fromMap(doc.data()))
          .toList();
    });
  }

  /// Get payment history as Future
  Future<List<PaymentHistory>> getPaymentHistoryFuture({
    String? type,
    int limit = 50,
  }) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      return [];
    }

    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(userId)
        .collection('payment_history')
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (type != null) {
      query = query.where('type', isEqualTo: type);
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => PaymentHistory.fromMap(doc.data()))
        .toList();
  }
}

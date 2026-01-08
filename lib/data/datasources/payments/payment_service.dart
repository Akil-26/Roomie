// Gateway-independent payment service abstraction.
//
// CRITICAL: This file NEVER depends on Stripe, Razorpay, or any specific gateway.
// It defines the interface that ALL payment gateways must implement.
//
// MIGRATION GUIDE:
// - To switch gateways: Only change the implementation in the specific service file
// - This abstraction ensures business logic stays STABLE
// - Payment creation, verification, and history work the same regardless of gateway

/// Payment result model - gateway independent
class PaymentResult {
  final bool success;
  final String? paymentId;        // Gateway-specific payment ID
  final String? orderId;          // Gateway-specific order ID  
  final String? clientSecret;     // For client-side payment confirmation (Stripe)
  final String? errorCode;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;

  const PaymentResult({
    required this.success,
    this.paymentId,
    this.orderId,
    this.clientSecret,
    this.errorCode,
    this.errorMessage,
    this.metadata,
  });

  factory PaymentResult.success({
    required String paymentId,
    String? orderId,
    String? clientSecret,
    Map<String, dynamic>? metadata,
  }) {
    return PaymentResult(
      success: true,
      paymentId: paymentId,
      orderId: orderId,
      clientSecret: clientSecret,
      metadata: metadata,
    );
  }

  factory PaymentResult.failure({
    required String errorCode,
    required String errorMessage,
  }) {
    return PaymentResult(
      success: false,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  factory PaymentResult.cancelled() {
    return const PaymentResult(
      success: false,
      errorCode: 'CANCELLED',
      errorMessage: 'Payment was cancelled by user',
    );
  }

  factory PaymentResult.requiresAction({
    required String paymentId,
    required String clientSecret,
  }) {
    return PaymentResult(
      success: false,
      paymentId: paymentId,
      clientSecret: clientSecret,
      errorCode: 'REQUIRES_ACTION',
      errorMessage: 'Additional authentication required',
    );
  }
}

/// Payment metadata for tracking and verification
class PaymentMetadata {
  final String odId;              // Payer user ID
  final String odName;            // Payer name
  final String recipientId;        // Recipient user ID
  final String recipientName;      // Recipient name
  final String? roomId;            // Room ID if room payment
  final String? chatId;            // Chat ID if chat payment
  final String? messageId;         // Message ID reference
  final String? month;             // Payment month (e.g., 'Jan-2026')
  final String paymentType;        // 'rent', 'maintenance', 'expense', etc.
  final String? note;              // Optional payment note

  const PaymentMetadata({
    required this.odId,
    required this.odName,
    required this.recipientId,
    required this.recipientName,
    this.roomId,
    this.chatId,
    this.messageId,
    this.month,
    required this.paymentType,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'user_id': odId,
      'user_name': odName,
      'recipient_id': recipientId,
      'recipient_name': recipientName,
      'room_id': roomId,
      'chat_id': chatId,
      'message_id': messageId,
      'month': month,
      'payment_type': paymentType,
      'note': note,
    };
  }

  factory PaymentMetadata.fromMap(Map<String, dynamic> map) {
    return PaymentMetadata(
      odId: map['user_id'] ?? '',
      odName: map['user_name'] ?? '',
      recipientId: map['recipient_id'] ?? '',
      recipientName: map['recipient_name'] ?? '',
      roomId: map['room_id'],
      chatId: map['chat_id'],
      messageId: map['message_id'],
      month: map['month'],
      paymentType: map['payment_type'] ?? 'unknown',
      note: map['note'],
    );
  }
}

/// Payment history record - gateway independent
class PaymentHistoryRecord {
  final String id;
  final String odId;
  final String odName;
  final String recipientId;
  final String recipientName;
  final double amount;
  final String currency;
  final String? note;
  final String gatewayPaymentId;   // Gateway-specific payment ID
  final String? gatewayOrderId;    // Gateway-specific order ID
  final String gateway;            // 'stripe', 'razorpay', etc.
  final String status;
  final String? chatId;
  final String? messageId;
  final String? roomId;
  final String paymentType;
  final DateTime createdAt;

  const PaymentHistoryRecord({
    required this.id,
    required this.odId,
    required this.odName,
    required this.recipientId,
    required this.recipientName,
    required this.amount,
    this.currency = 'INR',
    this.note,
    required this.gatewayPaymentId,
    this.gatewayOrderId,
    required this.gateway,
    required this.status,
    this.chatId,
    this.messageId,
    this.roomId,
    required this.paymentType,
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
      'paymentId': gatewayPaymentId,
      'orderId': gatewayOrderId,
      'gateway': gateway,
      'status': status,
      'chatId': chatId,
      'messageId': messageId,
      'roomId': roomId,
      'paymentType': paymentType,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory PaymentHistoryRecord.fromMap(Map<String, dynamic> map) {
    return PaymentHistoryRecord(
      id: map['id'] ?? '',
      odId: map['userId'] ?? '',
      odName: map['userName'] ?? '',
      recipientId: map['recipientId'] ?? '',
      recipientName: map['recipientName'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency'] ?? 'INR',
      note: map['note'],
      gatewayPaymentId: map['paymentId'] ?? '',
      gatewayOrderId: map['orderId'],
      gateway: map['gateway'] ?? 'unknown',
      status: map['status'] ?? 'unknown',
      chatId: map['chatId'],
      messageId: map['messageId'],
      roomId: map['roomId'],
      paymentType: map['paymentType'] ?? 'unknown',
      createdAt: map['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : DateTime.now(),
    );
  }
}

/// Abstract payment gateway interface.
/// 
/// Any payment gateway (Stripe, Razorpay, PayPal, etc.) must implement this.
/// This ensures the app can switch gateways without changing business logic.
abstract class PaymentGateway {
  /// Gateway identifier (e.g., 'stripe', 'razorpay')
  String get gatewayId;

  /// Whether the gateway is in test/sandbox mode
  bool get isTestMode;

  /// Initialize the payment gateway
  Future<void> initialize();

  /// Dispose/cleanup the payment gateway
  void dispose();

  /// Create a payment intent/order
  /// 
  /// [amount] - Amount in the currency's standard unit (e.g., INR, USD)
  /// [currency] - Currency code (e.g., 'INR', 'USD')
  /// [metadata] - Payment metadata for tracking
  /// 
  /// Returns a PaymentResult with client_secret for client-side confirmation
  Future<PaymentResult> createPayment({
    required double amount,
    required String currency,
    required PaymentMetadata metadata,
  });

  /// Verify a payment after client-side completion
  /// 
  /// [paymentId] - The gateway payment ID
  /// [paymentData] - Additional verification data (gateway-specific)
  /// 
  /// Returns true if payment is verified and successful
  Future<bool> verifyPayment({
    required String paymentId,
    Map<String, dynamic>? paymentData,
  });

  /// Get payment status
  /// 
  /// [paymentId] - The gateway payment ID
  /// 
  /// Returns the current status of the payment
  Future<String> getPaymentStatus(String paymentId);
}

/// Supported payment gateways
enum SupportedGateway {
  stripe,
  razorpay,
}

/// Payment gateway factory
/// 
/// Use this to get the current active payment gateway.
/// Change activeGateway to switch between gateways.
class PaymentGatewayFactory {
  static SupportedGateway activeGateway = SupportedGateway.stripe;

  /// Get the currently active payment gateway instance
  static PaymentGateway getGateway() {
    switch (activeGateway) {
      case SupportedGateway.stripe:
        // Import and return StripeService
        throw UnimplementedError('Import StripeService and return instance');
      case SupportedGateway.razorpay:
        // Import and return RazorpayService (from razorpay_old)
        throw UnimplementedError('Import RazorpayService and return instance');
    }
  }

  /// Switch to a different payment gateway
  static void switchGateway(SupportedGateway gateway) {
    activeGateway = gateway;
  }
}

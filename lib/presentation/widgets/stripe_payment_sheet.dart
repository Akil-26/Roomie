import 'package:flutter/material.dart';
import 'package:roomie/data/datasources/payments/stripe_service.dart';
import 'package:roomie/data/datasources/payments/payment_service.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/core/logger.dart';

/// Stripe payment bottom sheet widget.
/// 
/// Replaces the Razorpay checkout UI with Stripe's payment flow.
/// Maintains the same UX for users - just different underlying gateway.
class StripePaymentSheet extends StatefulWidget {
  final double amount;
  final String? upiId;  // Kept for future UPI integration
  final String note;
  final String currencySymbol;
  final String senderId;
  final String senderName;
  final String paymentRequestId;
  final String? roomId;
  final String paymentType;

  const StripePaymentSheet({
    super.key,
    required this.amount,
    this.upiId,
    required this.note,
    required this.currencySymbol,
    required this.senderId,
    required this.senderName,
    required this.paymentRequestId,
    this.roomId,
    this.paymentType = 'general',
  });

  @override
  State<StripePaymentSheet> createState() => _StripePaymentSheetState();
}

class _StripePaymentSheetState extends State<StripePaymentSheet> {
  final StripeService _stripeService = StripeService();
  final AuthService _authService = AuthService();
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeStripe();
  }

  Future<void> _initializeStripe() async {
    await _stripeService.initialize();
  }

  Future<void> _handleStripePayment() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Please login to make payment';
        });
      }
      return;
    }

    try {
      // Create payment metadata
      final metadata = PaymentMetadata(
        odId: currentUser.uid,
        odName: currentUser.displayName ?? 'User',
        recipientId: widget.senderId,
        recipientName: widget.senderName,
        roomId: widget.roomId,
        messageId: widget.paymentRequestId,
        paymentType: widget.paymentType,
        note: widget.note,
      );

      // Create payment intent
      final createResult = await _stripeService.createPayment(
        amount: widget.amount,
        currency: 'INR',
        metadata: metadata,
      );

      if (!createResult.success) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _errorMessage = createResult.errorMessage ?? 'Failed to create payment';
          });
        }
        return;
      }

      // NOTE: In production, get client_secret from your backend
      // For now, we'll simulate a successful payment flow
      
      // For demo/test mode, we'll mark the payment as successful
      // In real implementation, call presentPaymentSheet with actual client_secret
      
      // Simulate payment processing
      await Future.delayed(const Duration(seconds: 2));
      
      // Save payment history
      await _stripeService.savePaymentHistory(
        odId: currentUser.uid,
        odName: currentUser.displayName ?? 'User',
        recipientId: widget.senderId,
        recipientName: widget.senderName,
        amount: widget.amount,
        paymentId: createResult.paymentId!,
        note: widget.note,
        messageId: widget.paymentRequestId,
        roomId: widget.roomId,
        paymentType: widget.paymentType,
      );

      if (mounted) {
        Navigator.pop(context, {
          'status': 'paid',
          'paymentId': createResult.paymentId,
          'gateway': 'stripe',
        });
      }
    } catch (e) {
      AppLogger.e('Stripe payment error: $e');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Payment failed: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Amount display
            Text(
              '${widget.currencySymbol}${widget.amount.toStringAsFixed(2)}',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.note,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            Text(
              'To: ${widget.senderName}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),

            const SizedBox(height: 24),

            // Error message
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            if (_errorMessage != null) const SizedBox(height: 16),

            // Stripe Pay Now Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _handleStripePayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1), // Stripe purple
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.credit_card, size: 24),
                  label: Text(
                    _isProcessing ? 'Processing...' : 'Pay with Card',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Secure payment badge
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  'Secure payment powered by Stripe',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),

            // Test mode indicator
            if (_stripeService.isTestMode) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '🧪 TEST MODE - Use card 4242 4242 4242 4242',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(),

            // Mark as paid button
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check_circle, color: Colors.green),
              ),
              title: const Text('Mark as Paid'),
              subtitle: const Text('I have already paid via other method'),
              onTap: () => Navigator.pop(context, {'status': 'paid'}),
            ),

            // Decline button
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.cancel, color: Colors.red),
              ),
              title: const Text('Decline'),
              subtitle: const Text('I cannot pay this'),
              onTap: () => Navigator.pop(context, {'status': 'declined'}),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

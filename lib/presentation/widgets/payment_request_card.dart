import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:roomie/data/models/message_model.dart';
import 'package:roomie/data/datasources/razorpay_service.dart';
import 'package:roomie/data/datasources/auth_service.dart';

/// A widget that displays a payment request in chat
/// Shows amount, note, participants with payment status, and Pay Now button
class PaymentRequestCard extends StatelessWidget {
  final PaymentRequestData paymentRequest;
  final String currentUserId;
  final String senderId;
  final Map<String, String> memberNames;
  final bool isSentByMe;
  final Function(String odId, PaymentStatus newStatus)? onPaymentStatusChanged;

  const PaymentRequestCard({
    super.key,
    required this.paymentRequest,
    required this.currentUserId,
    required this.senderId,
    required this.memberNames,
    required this.isSentByMe,
    this.onPaymentStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currencySymbol =
        paymentRequest.currency == 'INR' ? '₹' : paymentRequest.currency;

    // Check if current user needs to pay
    final myParticipant =
        paymentRequest.participants
            .where((p) => p.odId == currentUserId)
            .firstOrNull;
    final needsToPay =
        myParticipant != null &&
        myParticipant.status == PaymentStatus.pending &&
        senderId != currentUserId;

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.primaryContainer.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with payment icon and amount
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.currency_rupee,
                    color: colorScheme.onPrimary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Request',
                        style: textTheme.labelMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer.withOpacity(
                            0.7,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$currencySymbol${paymentRequest.totalAmount.toStringAsFixed(2)}',
                        style: textTheme.headlineSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                _buildStatusBadge(context),
              ],
            ),
          ),

          // Note section
          if (paymentRequest.note != null && paymentRequest.note!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.note_outlined,
                    size: 16,
                    color: colorScheme.onPrimaryContainer.withOpacity(0.6),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      paymentRequest.note!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer.withOpacity(0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Participants section
          if (paymentRequest.participants.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Payment Status',
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...paymentRequest.participants.map((participant) {
              return _buildParticipantRow(context, participant, currencySymbol);
            }),
          ],

          // UPI ID if available
          if (paymentRequest.upiId != null && paymentRequest.upiId!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 16,
                    color: colorScheme.onPrimaryContainer.withOpacity(0.6),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'UPI: ${paymentRequest.upiId}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onPrimaryContainer.withOpacity(0.8),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),

          // Pay Now button (only for participants who haven't paid)
          if (needsToPay) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _handlePayNow(context, myParticipant),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.payment, size: 20),
                  label: Text(
                    'Pay $currencySymbol${myParticipant.amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ] else if (isSentByMe && !paymentRequest.isFullyPaid) ...[
            // Show summary for sender
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Received',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    Text(
                      '$currencySymbol${paymentRequest.paidAmount.toStringAsFixed(0)} / $currencySymbol${paymentRequest.totalAmount.toStringAsFixed(0)}',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final isFullyPaid = paymentRequest.isFullyPaid;
    final paidCount = paymentRequest.paidCount;
    final totalCount = paymentRequest.participants.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:
            isFullyPaid
                ? Colors.green.withOpacity(0.2)
                : Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFullyPaid ? Icons.check_circle : Icons.pending,
            size: 14,
            color: isFullyPaid ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 4),
          Text(
            isFullyPaid ? 'Complete' : '$paidCount/$totalCount',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isFullyPaid ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantRow(
    BuildContext context,
    PaymentParticipant participant,
    String currencySymbol,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final isPaid = participant.status == PaymentStatus.paid;
    final isDeclined = participant.status == PaymentStatus.declined;
    final displayName = memberNames[participant.odId] ?? participant.name;
    final isMe = participant.odId == currentUserId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color:
                  isPaid
                      ? Colors.green.withOpacity(0.2)
                      : isDeclined
                      ? Colors.red.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPaid
                  ? Icons.check
                  : isDeclined
                  ? Icons.close
                  : Icons.schedule,
              size: 14,
              color:
                  isPaid
                      ? Colors.green
                      : isDeclined
                      ? Colors.red
                      : Colors.grey,
            ),
          ),
          const SizedBox(width: 10),

          // Name
          Expanded(
            child: Text(
              isMe ? 'You' : displayName,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: isMe ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),

          // Amount
          Text(
            '$currencySymbol${participant.amount.toStringAsFixed(0)}',
            style: textTheme.bodyMedium?.copyWith(
              color: isPaid ? Colors.green : colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
              decoration: isPaid ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePayNow(
    BuildContext context,
    PaymentParticipant participant,
  ) async {
    // Show payment options dialog
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => _PaymentOptionsSheet(
            amount: participant.amount,
            upiId: paymentRequest.upiId,
            note: paymentRequest.note ?? 'Payment',
            currencySymbol:
                paymentRequest.currency == 'INR'
                    ? '₹'
                    : paymentRequest.currency,
            senderId: senderId,
            senderName: memberNames[senderId] ?? 'User',
            paymentRequestId: paymentRequest.id,
          ),
    );

    if (result != null && context.mounted) {
      if (result['status'] == 'paid') {
        // Update payment status
        onPaymentStatusChanged?.call(currentUserId, PaymentStatus.paid);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result['paymentId'] != null
                        ? 'Payment successful! ID: ${result['paymentId']}'
                        : 'Payment marked as complete!',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      } else if (result['status'] == 'declined') {
        onPaymentStatusChanged?.call(currentUserId, PaymentStatus.declined);
      }
    }
  }
}

/// Bottom sheet for payment options
class _PaymentOptionsSheet extends StatefulWidget {
  final double amount;
  final String? upiId;
  final String note;
  final String currencySymbol;
  final String senderId;
  final String senderName;
  final String paymentRequestId;

  const _PaymentOptionsSheet({
    required this.amount,
    this.upiId,
    required this.note,
    required this.currencySymbol,
    required this.senderId,
    required this.senderName,
    required this.paymentRequestId,
  });

  @override
  State<_PaymentOptionsSheet> createState() => _PaymentOptionsSheetState();
}

class _PaymentOptionsSheetState extends State<_PaymentOptionsSheet> {
  final RazorpayService _razorpayService = RazorpayService();
  final AuthService _authService = AuthService();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _razorpayService.initialize();
  }

  @override
  void dispose() {
    // Don't dispose razorpay here as it's a singleton
    super.dispose();
  }

  Future<void> _handleRazorpayPayment() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login to make payment'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isProcessing = false);
      }
      return;
    }

    _razorpayService.startPayment(
      amount: widget.amount,
      recipientName: widget.senderName,
      recipientId: widget.senderId,
      note: widget.note,
      messageId: widget.paymentRequestId,
      onComplete: (result) async {
        if (!mounted) return;

        setState(() => _isProcessing = false);

        if (result.success) {
          // Save payment history
          await _razorpayService.savePaymentHistory(
            odId: currentUser.uid,
            odName: currentUser.displayName ?? 'User',
            recipientId: widget.senderId,
            recipientName: widget.senderName,
            amount: widget.amount,
            paymentId: result.paymentId!,
            orderId: result.orderId,
            note: widget.note,
            messageId: widget.paymentRequestId,
          );

          if (mounted) {
            Navigator.pop(context, {
              'status': 'paid',
              'paymentId': result.paymentId,
            });
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result.errorCode == 'CANCELLED'
                      ? 'Payment cancelled'
                      : 'Payment failed: ${result.errorMessage}',
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
    );
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

            // Razorpay Pay Now Button (Primary)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _handleRazorpayPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF072654), // Razorpay blue
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
                      : const Icon(Icons.payment, size: 24),
                  label: Text(
                    _isProcessing ? 'Processing...' : 'Pay with Razorpay',
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
                  'Secure payment powered by Razorpay',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),

            // UPI Direct Option (Alternative)
            if (widget.upiId != null && widget.upiId!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  'Or pay directly via UPI',
                  style: textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _UpiAppButton(
                      name: 'GPay',
                      icon: Icons.g_mobiledata,
                      color: Colors.blue,
                      onTap: () => _launchUpiApp(context, 'gpay'),
                    ),
                    _UpiAppButton(
                      name: 'PhonePe',
                      icon: Icons.phone_android,
                      color: Colors.purple,
                      onTap: () => _launchUpiApp(context, 'phonepe'),
                    ),
                    _UpiAppButton(
                      name: 'Paytm',
                      icon: Icons.account_balance_wallet,
                      color: Colors.lightBlue,
                      onTap: () => _launchUpiApp(context, 'paytm'),
                    ),
                    _UpiAppButton(
                      name: 'Other',
                      icon: Icons.more_horiz,
                      color: Colors.grey,
                      onTap: () => _launchUpiApp(context, 'upi'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              const Divider(),
            ],

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

  Future<void> _launchUpiApp(BuildContext context, String app) async {
    if (widget.upiId == null || widget.upiId!.isEmpty) return;

    // Build UPI deep link
    final upiUrl = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': widget.upiId!, // Payee UPI ID
        'pn': 'Roomie Payment', // Payee name
        'am': widget.amount.toStringAsFixed(2), // Amount
        'cu': 'INR', // Currency
        'tn': widget.note, // Transaction note
      },
    );

    try {
      final launched = await launchUrl(
        upiUrl,
        mode: LaunchMode.externalApplication,
      );

      if (launched && context.mounted) {
        // Show confirmation dialog after returning from UPI app
        final confirmed = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Payment Complete?'),
                content: const Text(
                  'Did you complete the payment successfully?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('No'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Yes, Paid'),
                  ),
                ],
              ),
        );

        if (confirmed == true && context.mounted) {
          Navigator.pop(context, {'status': 'paid'});
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open UPI app. Please use Razorpay instead.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening UPI app. Please use Razorpay instead.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

/// UPI App button widget
class _UpiAppButton extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _UpiAppButton({
    required this.name,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

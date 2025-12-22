import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:roomie/data/datasources/upi_payment_service.dart';

/// Widget to show payment request card in chat with per-user status
class PaymentRequestCard extends StatefulWidget {
  final String messageId;
  final String chatId;
  final String requestId;
  final double amount;
  final String? note;
  final String senderName;
  final String senderId;
  final String? senderUpiId;
  final String? senderPhone;
  final Map<String, String> paymentStatus; // userId -> "PAID" or "PENDING"
  final List<String> toUsers; // Users who need to pay
  final Map<String, String> memberNames; // userId -> userName
  final String currentUserId;
  final bool isGroupChat;
  final bool isCompleted; // True when all users have paid

  const PaymentRequestCard({
    super.key,
    required this.messageId,
    required this.chatId,
    required this.requestId,
    required this.amount,
    this.note,
    required this.senderName,
    required this.senderId,
    this.senderUpiId,
    this.senderPhone,
    required this.paymentStatus,
    required this.toUsers,
    required this.memberNames,
    required this.currentUserId,
    required this.isGroupChat,
    this.isCompleted = false,
  });

  @override
  State<PaymentRequestCard> createState() => _PaymentRequestCardState();
}

class _PaymentRequestCardState extends State<PaymentRequestCard> {
  final UpiPaymentService _upiService = UpiPaymentService();
  bool _isProcessing = false;

  // Check if current user should see Pay Now button
  bool get _shouldShowPayButton {
    // Don't show if payment is completed
    if (widget.isCompleted) return false;
    
    // Don't show for sender
    if (widget.currentUserId == widget.senderId) return false;
    
    // Show only if current user is in toUsers list
    if (!widget.toUsers.contains(widget.currentUserId)) return false;
    
    // Check current user's payment status
    final status = widget.paymentStatus[widget.currentUserId];
    
    // Show button for: PENDING, CANCELLED, FAILED (allow retry)
    // Hide button for: PAID (prevent double payment)
    return status != 'PAID';
  }
  
  // Check if this is a retry scenario (CANCELLED or FAILED)
  bool get _isRetryScenario {
    final status = widget.paymentStatus[widget.currentUserId];
    return status == 'CANCELLED' || status == 'FAILED';
  }

  // Get payment status for a user
  String _getUserStatus(String userId) {
    return widget.paymentStatus[userId] ?? 'PENDING';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.primaryContainer, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Payment Request Title
            Row(
              children: [
                Icon(Icons.payment, color: colorScheme.primary, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Payment Request',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Amount and Note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '₹${widget.amount.toStringAsFixed(2)}',
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      if (widget.note != null && widget.note!.isNotEmpty)
                        Text(
                          widget.note!,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // Requested by
            Text(
              'Requested by ${widget.senderName}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            
            // Payment Status for each user
            ..._buildUserStatusList(),
            
            // Completed Banner (shows when all paid)
            if (widget.isCompleted) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Payment Completed ✅',
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // Pay Now Button (conditional - hidden when completed or already paid)
            if (_shouldShowPayButton) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _handlePayNow,
                  icon: _isProcessing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Icon(_isRetryScenario ? Icons.refresh : Icons.payment),
                  label: Text(
                    _isProcessing 
                      ? 'Processing...' 
                      : _isRetryScenario 
                        ? 'RETRY PAYMENT' 
                        : 'PAY NOW'
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRetryScenario 
                      ? Colors.orange 
                      : colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Build list of user statuses
  List<Widget> _buildUserStatusList() {
    final textTheme = Theme.of(context).textTheme;
    
    return widget.toUsers.map((userId) {
      final userName = widget.memberNames[userId] ?? 'Unknown';
      final status = _getUserStatus(userId);
      
      // Determine icon and color based on status
      IconData icon;
      Color color;
      String displayStatus;
      
      switch (status) {
        case 'PAID':
          icon = Icons.check_circle;
          color = Colors.green;
          displayStatus = 'PAID';
          break;
        case 'CANCELLED':
          icon = Icons.cancel;
          color = Colors.orange;
          displayStatus = 'CANCELLED';
          break;
        case 'FAILED':
          icon = Icons.error;
          color = Colors.red;
          displayStatus = 'FAILED';
          break;
        default: // PENDING
          icon = Icons.hourglass_empty;
          color = Colors.orange;
          displayStatus = 'PENDING';
      }
      
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                userName,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                displayStatus,
                style: textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Future<void> _handlePayNow() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // Step 1: Launch UPI payment first
      debugPrint('🚀 Launching UPI payment...');
      
      // 🔒 UPI ID validation info
      if (widget.senderUpiId == null || !widget.senderUpiId!.contains('@')) {
        debugPrint('ℹ️ No valid UPI ID (format: username@bank) provided.');
        debugPrint('   User will manually select recipient in UPI app.');
        debugPrint('   TIP: Add UPI ID field to user profile for auto-fill.');
      }
      
      final result = await _upiService.initiateUpiPayment(
        amount: widget.amount,
        payeeName: widget.senderName,
        payeePhoneNumber: widget.senderPhone,
        payeeUpiId: widget.senderUpiId,
        note: widget.note ?? 'Roomie Expenses',
      );

      // Handle UPI launch failure
      if (result == UpiPaymentResult.failed) {
        await _updatePaymentStatusSimple('FAILED');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️ Unable to open payment app\n'
                'Please check if UPI app is installed',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
        throw Exception('Failed to open payment app');
      }

      // Step 2: Show payment confirmation dialog
      if (mounted) {
        final confirmed = await _showPaymentConfirmationDialog();
        
        if (confirmed == true) {
          // Step 3: 🔒 Atomic transaction - Mark PAID + Create Expense
          debugPrint('💰 Processing payment success atomically...');
          await _processPaymentSuccess();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Payment recorded successfully'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else if (confirmed == false) {
          // User explicitly said NO - mark as CANCELLED
          debugPrint('❌ User cancelled payment');
          await _updatePaymentStatusSimple('CANCELLED');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  '💡 Payment cancelled\n'
                  'Common issues: Wrong PIN, Bank server down, Limit exceeded\n'
                  'Tap RETRY when ready',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
        // If null (dialog dismissed), do nothing - leave status as is
      }
    } catch (e) {
      debugPrint('❌ Error handling payment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// 🔒 Atomic transaction: Mark message PAID + Create expense
  Future<void> _processPaymentSuccess() async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // Determine message collection path
      final messagePath = widget.isGroupChat
          ? 'groups/${widget.chatId}/messages/${widget.messageId}'
          : 'chats/${widget.chatId}/messages/${widget.messageId}';
      
      await firestore.runTransaction((transaction) async {
        // Get message document
        final msgRef = firestore.doc(messagePath);
        final msgSnap = await transaction.get(msgRef);
        
        if (!msgSnap.exists) {
          throw Exception('Message not found');
        }
        
        final msgData = msgSnap.data()!;
        final currentStatus = msgData['paymentStatus'] as Map<String, dynamic>?;
        
        // 🛑 Idempotency guard - already paid?
        if (currentStatus?[widget.currentUserId] == 'PAID') {
          debugPrint('⚠️ Payment already marked as PAID - skipping');
          return;
        }
        
        debugPrint('✅ Step 1/3: Marking message as PAID');
        // Step 1: Mark message PAID
        transaction.update(msgRef, {
          'paymentStatus.${widget.currentUserId}': 'PAID',
          'paidAt.${widget.currentUserId}': FieldValue.serverTimestamp(),
        });
        
        debugPrint('✅ Step 2/3: Creating expense entry');
        // Step 2: Create expense entry
        final expenseRef = firestore.collection('expenses').doc();
        transaction.set(expenseRef, {
          'groupId': widget.chatId,
          'title': widget.note ?? 'Roomie expense',
          'amount': widget.amount,
          'paidBy': widget.currentUserId,
          'requestedBy': widget.senderId,
          'payeeName': widget.senderName,
          'linkedMessageId': widget.messageId,
          'participants': widget.toUsers,
          'isGroupPayment': widget.isGroupChat,
          'source': 'chat_payment',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
        debugPrint('✅ Step 3/3: Linking expense to message');
        // Step 3: Link expense to message
        transaction.update(msgRef, {
          'expenseId.${widget.currentUserId}': expenseRef.id,
        });
        
        debugPrint('🎉 Transaction committed successfully!');
      });
    } catch (e) {
      debugPrint('❌ Transaction failed: $e');
      rethrow;
    }
  }

  /// Simple status update for CANCELLED/FAILED (no expense creation)
  Future<void> _updatePaymentStatusSimple(String status) async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // Determine message collection path
      final messagePath = widget.isGroupChat
          ? 'groups/${widget.chatId}/messages/${widget.messageId}'
          : 'chats/${widget.chatId}/messages/${widget.messageId}';
      
      debugPrint('🔄 Updating payment status to $status for ${widget.currentUserId}');
      
      // Simple update - just change status (no transaction needed)
      await firestore.doc(messagePath).update({
        'paymentStatus.${widget.currentUserId}': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      debugPrint('✅ Status updated to $status');
    } catch (e) {
      debugPrint('❌ Failed to update status: $e');
      rethrow;
    }
  }

  Future<bool?> _showPaymentConfirmationDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Payment Confirmation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Did you complete the payment of ₹${widget.amount.toStringAsFixed(2)} to ${widget.senderName}?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.info_outline, size: 16, color: Colors.orange),
                      SizedBox(width: 6),
                      Text(
                        'If payment failed:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '• Check UPI PIN / Reset if needed\n'
                    '• Verify bank server is working\n'
                    '• Check daily transaction limits\n'
                    '• Try again after 10-15 minutes\n'
                    '• Switch to different UPI app',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('NO / FAILED'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('YES, PAID'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:roomie/data/models/message_model.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/presentation/widgets/payment_request_card.dart';

/// Screen that shows all payment requests from a specific chat
/// Makes it easy to find and pay pending requests
class ChatPaymentsScreen extends StatefulWidget {
  final String containerId;
  final String chatName;
  final bool isGroup;
  final Map<String, String> memberNames;

  const ChatPaymentsScreen({
    super.key,
    required this.containerId,
    required this.chatName,
    required this.isGroup,
    required this.memberNames,
  });

  @override
  State<ChatPaymentsScreen> createState() => _ChatPaymentsScreenState();
}

class _ChatPaymentsScreenState extends State<ChatPaymentsScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentUserId = _authService.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment Requests',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              widget.chatName,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Paid'),
            Tab(text: 'All'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Fetch all messages and filter locally to avoid composite index requirement
        stream: FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.containerId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            debugPrint('Error loading payments: ${snapshot.error}');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading payments',
                    style: TextStyle(color: colorScheme.error),
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          // Parse messages and extract payment requests only
          final paymentMessages = <_PaymentMessageData>[];
          for (final doc in docs) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              // Filter for payment request type
              if (data['type'] != 'paymentRequest') continue;
              
              final message = MessageModel.fromMap(data, doc.id);
              if (message.paymentRequest != null) {
                paymentMessages.add(
                  _PaymentMessageData(
                    message: message,
                    paymentRequest: message.paymentRequest!,
                  ),
                );
              }
            } catch (e) {
              debugPrint('Error parsing payment message: $e');
            }
          }

          if (paymentMessages.isEmpty) {
            return _buildEmptyState(context);
          }

          // Filter by status for tabs
          final pendingPayments =
              paymentMessages.where((p) {
                // Check if current user has pending payment
                final myParticipant =
                    p.paymentRequest.participants
                        .where((part) => part.odId == currentUserId)
                        .firstOrNull;
                return myParticipant?.status == PaymentStatus.pending;
              }).toList();

          final paidPayments =
              paymentMessages.where((p) {
                final myParticipant =
                    p.paymentRequest.participants
                        .where((part) => part.odId == currentUserId)
                        .firstOrNull;
                return myParticipant?.status == PaymentStatus.paid;
              }).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              // Pending tab
              _buildPaymentsList(
                context,
                pendingPayments,
                currentUserId,
                emptyMessage: 'No pending payments',
                emptyIcon: Icons.check_circle_outline,
              ),
              // Paid tab
              _buildPaymentsList(
                context,
                paidPayments,
                currentUserId,
                emptyMessage: 'No paid payments yet',
                emptyIcon: Icons.payment_outlined,
              ),
              // All tab
              _buildPaymentsList(
                context,
                paymentMessages,
                currentUserId,
                emptyMessage: 'No payment requests',
                emptyIcon: Icons.receipt_long_outlined,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No payment requests',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Payment requests from this chat\nwill appear here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsList(
    BuildContext context,
    List<_PaymentMessageData> payments,
    String currentUserId, {
    required String emptyMessage,
    required IconData emptyIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    if (payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              emptyIcon,
              size: 48,
              color: colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: payments.length,
      itemBuilder: (context, index) {
        final data = payments[index];
        final message = data.message;
        final paymentRequest = data.paymentRequest;
        final isSentByMe = message.senderId == currentUserId;

        // Get sender name
        final senderName =
            isSentByMe
                ? 'You'
                : widget.memberNames[message.senderId] ?? 'Unknown';

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sender info and time
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Row(
                  children: [
                    Text(
                      senderName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(paymentRequest.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              // Payment card
              PaymentRequestCard(
                paymentRequest: paymentRequest,
                currentUserId: currentUserId,
                senderId: message.senderId,
                memberNames: widget.memberNames,
                isSentByMe: isSentByMe,
                onPaymentStatusChanged: (userId, newStatus) {
                  _updatePaymentStatus(
                    message.id,
                    paymentRequest,
                    userId,
                    newStatus,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      // Today - show time
      final hour = date.hour > 12 ? date.hour - 12 : date.hour;
      final period = date.hour >= 12 ? 'PM' : 'AM';
      return '${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')} $period';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<void> _updatePaymentStatus(
    String messageId,
    PaymentRequestData paymentRequest,
    String odId,
    PaymentStatus newStatus,
  ) async {
    try {
      // Update participant status in the payment request
      final updatedParticipants =
          paymentRequest.participants.map((p) {
            if (p.odId == odId) {
              return p.copyWith(
                status: newStatus,
                paidAt: newStatus == PaymentStatus.paid ? DateTime.now() : null,
              );
            }
            return p;
          }).toList();

      final updatedPaymentRequest = PaymentRequestData(
        id: paymentRequest.id,
        totalAmount: paymentRequest.totalAmount,
        currency: paymentRequest.currency,
        note: paymentRequest.note,
        upiId: paymentRequest.upiId,
        phoneNumber: paymentRequest.phoneNumber,
        participants: updatedParticipants,
        createdAt: paymentRequest.createdAt,
      );

      // Update in Firestore
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.containerId)
          .collection('messages')
          .doc(messageId)
          .update({'paymentRequest': updatedPaymentRequest.toMap()});
    } catch (e) {
      debugPrint('Error updating payment status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update payment: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

/// Helper class to hold message and payment request data together
class _PaymentMessageData {
  final MessageModel message;
  final PaymentRequestData paymentRequest;

  _PaymentMessageData({required this.message, required this.paymentRequest});
}

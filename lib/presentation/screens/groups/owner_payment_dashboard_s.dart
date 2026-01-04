import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:roomie/data/datasources/room_payment_service.dart';
import 'package:roomie/data/models/payment_record_model.dart';

/// Owner dashboard to see all payment records for their room.
/// 
/// STEP-3 PAYMENT BOUNDARY - OWNER VIEW:
/// - See ALL payment records for the room
/// - See who paid / who didn't
/// - Room rent amount display
/// 
/// VISIBILITY RULES:
/// - Owner can see all payments for rooms they own
/// - This screen is ONLY accessible to room owner
class OwnerPaymentDashboardScreen extends StatefulWidget {
  final String roomId;
  final String roomName;

  const OwnerPaymentDashboardScreen({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  State<OwnerPaymentDashboardScreen> createState() => _OwnerPaymentDashboardScreenState();
}

class _OwnerPaymentDashboardScreenState extends State<OwnerPaymentDashboardScreen> {
  final RoomPaymentService _paymentService = RoomPaymentService();
  
  bool _isLoading = true;
  bool _isOwner = false;
  List<PaymentRecordModel> _allPayments = [];
  Map<String, dynamic> _paymentSummary = {};
  Map<String, dynamic> _roomDetails = {};
  final Map<String, Map<String, dynamic>?> _userDetailsCache = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Verify user is owner
      final isOwner = await _paymentService.isRoomOwner(widget.roomId);
      if (!isOwner) {
        if (mounted) {
          setState(() {
            _isOwner = false;
            _isLoading = false;
          });
        }
        return;
      }

      // Get room details
      final roomDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.roomId)
          .get();
      
      // Get all payments
      final payments = await _paymentService.getRoomPayments(widget.roomId);
      
      // Get payment summary
      final summary = await _paymentService.getRoomPaymentSummary(widget.roomId);

      // Fetch user details for each payer
      for (final payment in payments) {
        if (!_userDetailsCache.containsKey(payment.payerId)) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(payment.payerId)
              .get();
          _userDetailsCache[payment.payerId] = userDoc.data();
        }
      }

      if (mounted) {
        setState(() {
          _isOwner = true;
          _roomDetails = roomDoc.data() ?? {};
          _allPayments = payments;
          _paymentSummary = summary;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading owner payment data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getPayerName(String payerId) {
    final details = _userDetailsCache[payerId];
    return details?['username'] ?? details?['name'] ?? 'Unknown User';
  }

  String? _getPayerPhoto(String payerId) {
    final details = _userDetailsCache[payerId];
    return details?['photoURL'] ?? details?['profileImageUrl'];
  }

  String _getCurrencySymbol(String? currency) {
    switch ((currency ?? 'INR').toUpperCase()) {
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'INR':
      default:
        return '₹';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_isOwner
              ? _buildNotOwnerView()
              : _buildOwnerDashboard(),
    );
  }

  Widget _buildNotOwnerView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Access Denied',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Only the room owner can access this dashboard.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerDashboard() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary card
            _buildSummaryCard(),
            
            const SizedBox(height: 24),
            
            // Room rent info
            _buildRentInfoCard(),
            
            const SizedBox(height: 24),
            
            // All payments
            _buildAllPaymentsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final totalCollected = (_paymentSummary['totalCollected'] as num?)?.toDouble() ?? 0;
    final paymentCount = _paymentSummary['paymentCount'] ?? 0;
    final currency = _paymentSummary['currency'] ?? 'INR';
    final symbol = _getCurrencySymbol(currency);
    final monthYear = _paymentSummary['monthYear'] ?? '';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.blue[700],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'This Month',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                if (monthYear.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      monthYear,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '$symbol${totalCollected.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Collected from $paymentCount payment${paymentCount == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRentInfoCard() {
    final rentAmount = (_roomDetails['rentAmount'] as num?)?.toDouble() ?? 0;
    final currency = _roomDetails['rentCurrency'] ?? 'INR';
    final symbol = _getCurrencySymbol(currency);
    final memberCount = (_roomDetails['memberCount'] as num?)?.toInt() ?? 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.home, color: Colors.green),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Room Info',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    'Monthly Rent',
                    '$symbol${rentAmount.toStringAsFixed(0)}',
                    Icons.attach_money,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildInfoItem(
                    'Members',
                    '$memberCount',
                    Icons.people,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllPaymentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'All Payments',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${_allPayments.length} total',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        if (_allPayments.isEmpty)
          _buildEmptyPayments()
        else
          ..._allPayments.map((payment) => _buildPaymentItem(payment)),
      ],
    );
  }

  Widget _buildEmptyPayments() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No Payments Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Payments from roommates will appear here.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentItem(PaymentRecordModel payment) {
    final payerName = _getPayerName(payment.payerId);
    final payerPhoto = _getPayerPhoto(payment.payerId);
    final formattedDate = DateFormat('MMM d, yyyy • h:mm a').format(payment.createdAt);
    final statusColor = _getStatusColor(payment.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Payer avatar
            CircleAvatar(
              radius: 24,
              backgroundImage: payerPhoto != null ? NetworkImage(payerPhoto) : null,
              child: payerPhoto == null
                  ? Text(
                      payerName.isNotEmpty ? payerName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 18),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            
            // Payment details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    payerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    payment.purpose.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    formattedDate,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                  if (payment.note != null && payment.note!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '"${payment.note}"',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            
            // Amount and status
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  payment.formattedAmount,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: payment.isSuccess ? Colors.green[700] : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    payment.status.displayName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.pending:
        return Colors.orange;
      case PaymentStatus.success:
        return Colors.green;
      case PaymentStatus.failed:
        return Colors.red;
    }
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:roomie/data/datasources/room_payment_service.dart';
import 'package:roomie/data/datasources/payments/razorpay_service.dart';
import 'package:roomie/data/models/payment_record_model.dart';
import 'package:roomie/presentation/widgets/empty_states.dart';
import 'package:roomie/presentation/widgets/action_guard.dart';

/// Screen for roommates to pay rent and view their own payment history.
/// 
/// STEP-3 PAYMENT BOUNDARY - ROOMMATE VIEW:
/// - "Pay Rent" button
/// - Own payment history (only their payments)
/// - Owner details visible
/// 
/// VISIBILITY RULES:
/// - Roommates only see their OWN payments
/// - Cannot see other roommates' payments
/// - Cannot see owner financial settings
/// 
/// STEP-6: Safety Guards:
/// - Double-payment protection
/// - UI lock during payment processing
/// - App resume re-checks
class RoomPaymentsScreen extends StatefulWidget {
  final String roomId;
  final String roomName;

  const RoomPaymentsScreen({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  State<RoomPaymentsScreen> createState() => _RoomPaymentsScreenState();
}

class _RoomPaymentsScreenState extends State<RoomPaymentsScreen> 
    with WidgetsBindingObserver, ActionGuardMixin {
  final RoomPaymentService _paymentService = RoomPaymentService();
  final RazorpayService _razorpayService = RazorpayService();
  
  bool _isLoading = true;
  bool _canMakePayment = false;
  Map<String, dynamic>? _ownerDetails;
  List<PaymentRecordModel> _myPayments = [];

  @override
  void initState() {
    super.initState();
    // STEP-6: Register for app lifecycle events
    WidgetsBinding.instance.addObserver(this);
    _razorpayService.initialize();
    _loadData();
  }

  // STEP-6: App Background/Resume Safety
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Re-load data when app resumes to get fresh payment state
      _loadData();
    }
  }

  @override
  void dispose() {
    // STEP-6: Cleanup lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    // Don't dispose razorpay here as it's a singleton
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Check if payments can be made (room has owner)
      final canPay = await _paymentService.canMakePayment(widget.roomId);
      
      // Get owner details if room has owner
      Map<String, dynamic>? ownerDetails;
      if (canPay) {
        ownerDetails = await _paymentService.getRoomOwnerDetails(widget.roomId);
      }

      // Get my payment history
      final payments = await _paymentService.getMyPaymentHistory(widget.roomId);

      if (mounted) {
        setState(() {
          _canMakePayment = canPay;
          _ownerDetails = ownerDetails;
          _myPayments = payments;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading payment data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showPaymentDialog() async {
    if (_ownerDetails == null) return;

    final rentAmount = (_ownerDetails!['rentAmount'] as num?)?.toDouble() ?? 0;
    final currency = _ownerDetails!['rentCurrency'] ?? 'INR';
    final ownerName = _ownerDetails!['ownerName'] ?? 'Owner';
    
    // Allow custom amount or use rent amount
    final amountController = TextEditingController(
      text: rentAmount > 0 ? rentAmount.toStringAsFixed(0) : '',
    );
    final noteController = TextEditingController();
    PaymentPurpose selectedPurpose = PaymentPurpose.rent;

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Make Payment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Owner info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Paying to',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            Text(
                              ownerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Payment purpose
                const Text(
                  'Payment For',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildPurposeOption(
                        'Rent',
                        Icons.home,
                        selectedPurpose == PaymentPurpose.rent,
                        () => setDialogState(() => selectedPurpose = PaymentPurpose.rent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPurposeOption(
                        'Maintenance',
                        Icons.build,
                        selectedPurpose == PaymentPurpose.maintenance,
                        () => setDialogState(() => selectedPurpose = PaymentPurpose.maintenance),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Amount input
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: _getCurrencySymbol(currency),
                    border: const OutlineInputBorder(),
                    helperText: rentAmount > 0 
                        ? 'Monthly rent: ${_getCurrencySymbol(currency)}${rentAmount.toStringAsFixed(0)}'
                        : null,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Note input (optional)
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'e.g., January rent payment',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid amount')),
                  );
                  return;
                }
                Navigator.of(context).pop({
                  'amount': amount,
                  'purpose': selectedPurpose,
                  'note': noteController.text.isNotEmpty ? noteController.text : null,
                });
              },
              child: const Text('Pay Now'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _processPayment(
        amount: result['amount'],
        purpose: result['purpose'],
        note: result['note'],
      );
    }
  }

  Widget _buildPurposeOption(
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withAlpha(30) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.blue : Colors.grey),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processPayment({
    required double amount,
    required PaymentPurpose purpose,
    String? note,
  }) async {
    // STEP-6: Double-payment protection
    // Defensive assertion: prevent payment if owner details missing
    if (_ownerDetails == null || _ownerDetails!['ownerId'] == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot process payment: Owner details unavailable'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Use guarded action for double-tap prevention
    await guardedAction<void>(
      'pay_rent',
      () async {
        await _paymentService.processPayment(
          roomId: widget.roomId,
          roomName: widget.roomName,
          ownerId: _ownerDetails!['ownerId'],
          ownerName: _ownerDetails!['ownerName'] ?? 'Owner',
          amount: amount,
          currency: _ownerDetails!['rentCurrency'] ?? 'INR',
          purpose: purpose,
          note: note,
          onComplete: (success, message) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message ?? (success ? 'Payment successful' : 'Payment failed')),
                  backgroundColor: success ? Colors.green : Colors.red,
                ),
              );

              if (success) {
                _loadData(); // Refresh payment history
              }
            }
          },
        );
      },
      onError: (e) {
        if (mounted) {
          showNetworkErrorSnackbar(context, message: 'Payment failed. Please check your connection.');
        }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
        centerTitle: true,
      ),
      // STEP-6: UI Lock during payment processing (soft visual blocker)
      body: CriticalActionOverlay(
        isActive: isActionInProgress('pay_rent'),
        message: 'Processing payment...',
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // STEP-5: Flow explanation text (tiny onboarding)
            const FlowExplanationCard(
              icon: Icons.info_outline,
              text: 'Payments are handled by the room owner. You can only see your own payments.',
              color: Colors.blue,
            ),
            const SizedBox(height: 16),
            
            // Pay Rent section (only if room has owner)
            if (_canMakePayment && _ownerDetails != null)
              _buildPaymentCard()
            else
              _buildNoOwnerCard(),

            const SizedBox(height: 24),

            // Payment History section
            _buildPaymentHistorySection(),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard() {
    final ownerName = _ownerDetails!['ownerName'] ?? 'Owner';
    final rentAmount = (_ownerDetails!['rentAmount'] as num?)?.toDouble() ?? 0;
    final currency = _ownerDetails!['rentCurrency'] ?? 'INR';
    final symbol = _getCurrencySymbol(currency);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.payment, color: Colors.blue, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pay Rent',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'to $ownerName',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            if (rentAmount > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Monthly Rent'),
                    Text(
                      '$symbol${rentAmount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // STEP-6: Pay button with double-tap protection
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isActionInProgress('pay_rent') ? null : _showPaymentDialog,
                icon: isActionInProgress('pay_rent')
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.credit_card),
                label: Text(isActionInProgress('pay_rent') ? 'Processing...' : 'Pay Now'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoOwnerCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No Owner Set',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This room doesn\'t have an owner yet. '
              'Payments will be available once an owner is approved.',
              textAlign: TextAlign.center,
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

  Widget _buildPaymentHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'My Payment History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${_myPayments.length} payments',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // STEP-5: Improved empty state for payments
        if (_myPayments.isEmpty)
          const EmptyPaymentsState()
        else
          ..._myPayments.map((payment) => _buildPaymentHistoryItem(payment)),
      ],
    );
  }

  Widget _buildPaymentHistoryItem(PaymentRecordModel payment) {
    final formattedDate = DateFormat('MMM d, yyyy').format(payment.createdAt);
    final statusColor = _getStatusColor(payment.status);
    final statusIcon = _getStatusIcon(payment.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: statusColor.withAlpha(30),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(statusIcon, color: statusColor),
        ),
        title: Text(
          payment.formattedAmount,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              payment.purpose.displayName,
              style: TextStyle(color: Colors.grey[600]),
            ),
            Text(
              formattedDate,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            if (payment.note != null && payment.note!.isNotEmpty)
              Text(
                payment.note!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            payment.status.displayName.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
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

  IconData _getStatusIcon(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.pending:
        return Icons.hourglass_empty;
      case PaymentStatus.success:
        return Icons.check_circle;
      case PaymentStatus.failed:
        return Icons.error;
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PaymentRequestBottomSheet extends StatefulWidget {
  final List<Map<String, dynamic>> groupMembers; // [{id, name}]
  final String currentUserId;
  final Function(double amount, List<String> selectedUserIds, String description) onSendRequest;

  const PaymentRequestBottomSheet({
    Key? key,
    required this.groupMembers,
    required this.currentUserId,
    required this.onSendRequest,
  }) : super(key: key);

  @override
  State<PaymentRequestBottomSheet> createState() => _PaymentRequestBottomSheetState();
}

class _PaymentRequestBottomSheetState extends State<PaymentRequestBottomSheet> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final Set<String> _selectedUserIds = {};
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    // Select all by default
    _selectAll = true;
    _selectedUserIds.addAll(
      widget.groupMembers
          .where((member) => member['id'] != widget.currentUserId)
          .map((member) => member['id'] as String),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedUserIds.addAll(
          widget.groupMembers
              .where((member) => member['id'] != widget.currentUserId)
              .map((member) => member['id'] as String),
        );
      } else {
        _selectedUserIds.clear();
      }
    });
  }

  void _toggleUser(String userId, bool? value) {
    setState(() {
      if (value == true) {
        _selectedUserIds.add(userId);
      } else {
        _selectedUserIds.remove(userId);
      }
      // Update select all checkbox state
      final selectableCount = widget.groupMembers
          .where((member) => member['id'] != widget.currentUserId)
          .length;
      _selectAll = _selectedUserIds.length == selectableCount;
    });
  }

  void _handleSend() {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter amount')),
      );
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid amount')),
      );
      return;
    }

    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one person')),
      );
      return;
    }

    final description = _descriptionController.text.trim();
    widget.onSendRequest(amount, _selectedUserIds.toList(), description);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Filter out current user
    final selectableMembers = widget.groupMembers
        .where((member) => member['id'] != widget.currentUserId)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Request Payment',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Amount Input
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100],
                ),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Description Input
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'What is this payment for?',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100],
                ),
              ),
              const SizedBox(height: 20),

              // Select People Section
              Text(
                'Request from:',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Select All Checkbox
              if (selectableMembers.length > 1)
                CheckboxListTile(
                  title: const Text('Select All'),
                  value: _selectAll,
                  onChanged: _toggleSelectAll,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),

              // Member List
              Container(
                constraints: const BoxConstraints(maxHeight: 250),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: selectableMembers.length,
                  itemBuilder: (context, index) {
                    final member = selectableMembers[index];
                    final userId = member['id'] as String;
                    final userName = member['name'] as String;
                    
                    return CheckboxListTile(
                      title: Text(userName),
                      value: _selectedUserIds.contains(userId),
                      onChanged: (value) => _toggleUser(userId, value),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),

              // Send Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleSend,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Send Request',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

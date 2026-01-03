import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:roomie/data/models/message_model.dart';
import 'package:uuid/uuid.dart';

/// Dialog for creating a payment request in chat
class CreatePaymentRequestDialog extends StatefulWidget {
  final bool isGroup;
  final List<String> memberIds;
  final Map<String, String> memberNames;
  final String currentUserId;
  final String? defaultUpiId;

  const CreatePaymentRequestDialog({
    super.key,
    required this.isGroup,
    required this.memberIds,
    required this.memberNames,
    required this.currentUserId,
    this.defaultUpiId,
  });

  @override
  State<CreatePaymentRequestDialog> createState() =>
      _CreatePaymentRequestDialogState();
}

class _CreatePaymentRequestDialogState extends State<CreatePaymentRequestDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _upiIdController = TextEditingController();

  bool _splitEqually = true;
  final Map<String, double> _customAmounts = {};
  Set<String> _selectedParticipants = {};

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
    _slideController.forward();

    if (widget.defaultUpiId != null) {
      _upiIdController.text = widget.defaultUpiId!;
    }

    if (!widget.isGroup) {
      final otherId = widget.memberIds.firstWhere(
        (id) => id != widget.currentUserId,
        orElse: () => '',
      );
      if (otherId.isNotEmpty) {
        _selectedParticipants.add(otherId);
      }
    } else {
      _selectedParticipants =
          widget.memberIds.where((id) => id != widget.currentUserId).toSet();
    }

    for (final id in widget.memberIds) {
      if (id != widget.currentUserId) {
        _customAmounts[id] = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _upiIdController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _updateCustomAmounts() {
    if (_splitEqually && _selectedParticipants.isNotEmpty) {
      final totalAmount = double.tryParse(_amountController.text) ?? 0.0;
      final perPerson = totalAmount / _selectedParticipants.length;

      for (final id in _customAmounts.keys) {
        if (_selectedParticipants.contains(id)) {
          _customAmounts[id] = perPerson;
        } else {
          _customAmounts[id] = 0.0;
        }
      }
    }
  }

  // Calculate total from custom amounts and update the amount field
  void _updateTotalFromCustomAmounts() {
    if (!_splitEqually) {
      double total = 0.0;
      for (final id in _selectedParticipants) {
        total += _customAmounts[id] ?? 0.0;
      }
      _amountController.text = total > 0 ? total.toStringAsFixed(2) : '';
      setState(() {});
    }
  }

  void _createPaymentRequest() {
    if (!_formKey.currentState!.validate()) return;

    final totalAmount = double.tryParse(_amountController.text) ?? 0.0;
    if (totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid amount'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_selectedParticipants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one participant'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _updateCustomAmounts();

    final participants = <PaymentParticipant>[];
    for (final id in _selectedParticipants) {
      final amount = _customAmounts[id] ?? 0.0;
      if (amount > 0) {
        participants.add(
          PaymentParticipant(
            odId: id,
            name: widget.memberNames[id] ?? 'User',
            amount: amount,
            status: PaymentStatus.pending,
          ),
        );
      }
    }

    if (participants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please assign amounts to participants'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final paymentRequest = PaymentRequestData(
      id: const Uuid().v4(),
      totalAmount: totalAmount,
      currency: 'INR',
      note:
          _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
      upiId:
          _upiIdController.text.trim().isEmpty
              ? null
              : _upiIdController.text.trim(),
      participants: participants,
      createdAt: DateTime.now(),
    );

    Navigator.of(context).pop(paymentRequest);
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final totalAmount = double.tryParse(_amountController.text) ?? 0.0;

    return SlideTransition(
      position: _slideAnimation,
      child: Dialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Icon(
                          Icons.payment_rounded,
                          color: colorScheme.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Request Payment',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Amount field
                    Text(
                      'Amount',
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'),
                        ),
                      ],
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        prefixStyle: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                        hintText: '0.00',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter amount';
                        }
                        final amount = double.tryParse(value);
                        if (amount == null || amount <= 0) {
                          return 'Enter valid amount';
                        }
                        return null;
                      },
                      onChanged: (_) {
                        if (_splitEqually) {
                          setState(() => _updateCustomAmounts());
                        }
                      },
                    ),

                    const SizedBox(height: 12),

                    // Note field
                    Text(
                      'Note (optional)',
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _noteController,
                      maxLines: 1,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.sentences,
                      style: textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'e.g., Dinner, Movie',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        counterText: '',
                      ),
                    ),

                    const SizedBox(height: 12),

                    // UPI ID field
                    Text(
                      'UPI ID (optional)',
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _upiIdController,
                      keyboardType: TextInputType.emailAddress,
                      style: textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'yourname@upi',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),

                    // Participants section (for groups)
                    if (widget.isGroup) ...[
                      const SizedBox(height: 14),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Split between',
                            style: textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Equal', style: textTheme.labelSmall),
                              SizedBox(
                                height: 28,
                                child: Switch(
                                  value: _splitEqually,
                                  onChanged: (value) {
                                    setState(() {
                                      _splitEqually = value;
                                      if (value) _updateCustomAmounts();
                                    });
                                  },
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Summary text
                      if (_selectedParticipants.isNotEmpty && totalAmount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 6),
                          child: Text(
                            '${_selectedParticipants.length} people • ₹${(totalAmount / _selectedParticipants.length).toStringAsFixed(2)} each',
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                        ),

                      const SizedBox(height: 6),

                      // Participants list
                      Container(
                        constraints: const BoxConstraints(maxHeight: 150),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: colorScheme.outline.withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: widget.memberIds.length,
                          separatorBuilder:
                              (_, _) => Divider(
                                height: 1,
                                color: colorScheme.outline.withOpacity(0.15),
                              ),
                          itemBuilder: (context, index) {
                            final memberId = widget.memberIds[index];
                            if (memberId == widget.currentUserId) {
                              return const SizedBox.shrink();
                            }

                            final isSelected = _selectedParticipants.contains(
                              memberId,
                            );
                            final memberName =
                                widget.memberNames[memberId] ?? 'User';
                            final amount = _customAmounts[memberId] ?? 0.0;

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedParticipants.remove(memberId);
                                  } else {
                                    _selectedParticipants.add(memberId);
                                  }
                                  if (_splitEqually) _updateCustomAmounts();
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor:
                                          colorScheme.primaryContainer,
                                      child: Text(
                                        _getInitials(memberName),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            memberName,
                                            style: textTheme.bodySmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (isSelected && _splitEqually)
                                            Text(
                                              '₹${amount.toStringAsFixed(2)}',
                                              style: textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: colorScheme.primary,
                                                  ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected && !_splitEqually) ...[
                                      SizedBox(
                                        width: 70,
                                        height: 28,
                                        child: TextField(
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          textAlign: TextAlign.end,
                                          style: textTheme.labelSmall,
                                          decoration: InputDecoration(
                                            prefixText: '₹',
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 6,
                                                ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                          ),
                                          onChanged: (value) {
                                            _customAmounts[memberId] =
                                                double.tryParse(value) ?? 0.0;
                                            _updateTotalFromCustomAmounts();
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Checkbox(
                                        value: isSelected,
                                        onChanged: (value) {
                                          setState(() {
                                            if (value == true) {
                                              _selectedParticipants.add(
                                                memberId,
                                              );
                                            } else {
                                              _selectedParticipants.remove(
                                                memberId,
                                              );
                                            }
                                            if (_splitEqually) {
                                              _updateCustomAmounts();
                                            }
                                          });
                                        },
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 18),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _createPaymentRequest,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              totalAmount > 0
                                  ? 'Request ₹${totalAmount.toStringAsFixed(0)}'
                                  : 'Request Payment',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

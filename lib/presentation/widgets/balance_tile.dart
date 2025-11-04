import 'package:flutter/material.dart';
import 'package:roomie/data/models/expense_model.dart';

/// Instagram-inspired, theme-compliant balance tile widget
class BalanceTile extends StatelessWidget {
  final UserBalance balance;
  final VoidCallback? onTap;

  const BalanceTile({super.key, required this.balance, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPositive = balance.netBalance >= 0;
    final netBalance = balance.netBalance;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 26,
                backgroundColor: _getUserColor(context, balance.userName),
                child: Text(
                  _getInitials(balance.userName),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // User info and breakdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      balance.userName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildBreakdownItem(
                          context,
                          label: 'Paid',
                          amount: balance.totalPaid,
                          icon: Icons.arrow_upward_rounded,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        _buildBreakdownItem(
                          context,
                          label: 'Owes',
                          amount: balance.totalOwed,
                          icon: Icons.arrow_downward_rounded,
                          color: colorScheme.error,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Net balance
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "${isPositive ? '+ ' : '- '}₹${netBalance.abs().toStringAsFixed(2)}",
                    style: theme.textTheme.titleMedium?.copyWith(
                      color:
                          isPositive
                              ? colorScheme.secondary
                              : colorScheme.error,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isPositive ? 'To Receive' : 'To Pay',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Returns a color for the user avatar based on the username (Instagram-inspired)
  Color _getUserColor(BuildContext context, String userName) {
    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
      Theme.of(context).colorScheme.tertiary,
      Theme.of(context).colorScheme.primaryContainer,
      Theme.of(context).colorScheme.secondaryContainer,
      Theme.of(context).colorScheme.tertiaryContainer,
    ];
    final hash = userName.codeUnits.fold(0, (prev, c) => prev + c);
    return colors[hash % colors.length];
  }

  /// Returns initials from a username
  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  /// Widget for breakdown item (Paid/Owes)
  Widget _buildBreakdownItem(
    BuildContext context, {
    required String label,
    required double amount,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Text(
          '$label: ₹${amount.toStringAsFixed(2)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

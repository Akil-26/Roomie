import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/expense_service.dart';
import 'package:roomie/data/models/expense_model.dart';
import 'package:roomie/presentation/widgets/expense_card.dart';

class UserExpensesScreen extends StatefulWidget {
  const UserExpensesScreen({super.key});

  @override
  State<UserExpensesScreen> createState() => _UserExpensesScreenState();
}

class _UserExpensesScreenState extends State<UserExpensesScreen> {
  final ExpenseService _expenseService = ExpenseService();
  List<ExpenseModel> _expenses = [];
  bool _isLoading = true;
  double _totalSpent = 0.0; // You paid
  double _totalReceived = 0.0; // Others paid you

  @override
  void initState() {
    super.initState();
    _loadUserExpenses();
  }

  Future<void> _loadUserExpenses() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      if (currentUser == null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      // Subscribe once and compute summary
      _expenseService.getUserExpenses(currentUser.uid).listen((list) {
        double spent = 0.0;
        double received = 0.0;

        for (final exp in list) {
          // Spent: your paid share on any expense where you are a participant and marked paid
          final myShare = exp.splitAmounts[currentUser.uid] ?? 0.0;
          final iPaid = exp.paymentStatus[currentUser.uid] == true;
          if (iPaid) {
            spent += myShare;
          }

          // Received: other participants paid their shares on expenses you created
          if (exp.createdBy == currentUser.uid) {
            for (final p in exp.participants) {
              if (p == currentUser.uid) continue;
              final pPaid = exp.paymentStatus[p] == true;
              if (pPaid) {
                received += (exp.splitAmounts[p] ?? 0.0);
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _expenses = list;
            _totalSpent = spent;
            _totalReceived = received;
            _isLoading = false;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading expenses: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Expenses'),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      backgroundColor: cs.surface,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _UserExpenseSummary(
                    totalSpent: _totalSpent,
                    totalReceived: _totalReceived,
                  ),
                ),
                Expanded(
                  child: _expenses.isEmpty
                      ? Center(
                          child: Text(
                            'No expenses yet',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          itemCount: _expenses.length,
                          itemBuilder: (context, index) {
                            return ExpenseCard(expense: _expenses[index]);
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _UserExpenseSummary extends StatelessWidget {
  final double totalSpent;
  final double totalReceived;

  const _UserExpenseSummary({
    required this.totalSpent,
    required this.totalReceived,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final net = totalReceived - totalSpent;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _metric(
              context,
              label: 'Spent',
              value: totalSpent,
              valueColor: cs.error,
              icon: Icons.arrow_upward,
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: cs.outlineVariant,
          ),
          Expanded(
            child: _metric(
              context,
              label: 'Received',
              value: totalReceived,
              valueColor: cs.primary,
              icon: Icons.arrow_downward,
            ),
          ),
          const SizedBox(width: 8),
          Chip(
            label: Text(
              'Net ${net >= 0 ? '+' : ''}${net.toStringAsFixed(2)}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: net >= 0 ? cs.onPrimaryContainer : cs.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor:
                net >= 0 ? cs.primaryContainer : cs.errorContainer,
          ),
        ],
      ),
    );
  }

  Widget _metric(
    BuildContext context, {
    required String label,
    required double value,
    required Color valueColor,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: valueColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: valueColor, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value.toStringAsFixed(2),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:roomie/data/models/expense_model.dart';
import 'package:intl/intl.dart';

class ExpenseCard extends StatelessWidget {
  final ExpenseModel expense;

  const ExpenseCard({super.key, required this.expense});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(expense.title),
        subtitle: Text('\$${expense.amount.toStringAsFixed(2)}'),
        trailing: Text(DateFormat('MMM dd').format(expense.createdAt)),
      ),
    );
  }
}

class ExpenseSummaryCard extends StatelessWidget {
  final Map<String, dynamic> summary;

  const ExpenseSummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final balance = summary['balance']?.toDouble() ?? 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Balance: \$${balance.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:roomie/data/models/expense_model.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class ExpenseCard extends StatelessWidget {
  final ExpenseModel expense;
  final String? paymentUrl;

  const ExpenseCard({super.key, required this.expense, this.paymentUrl});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Card(
      child: ListTile(
        title: Text(
          expense.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '\$${expense.amount.toStringAsFixed(2)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: ConstrainedBox(
          // Limit trailing width so the tile can layout on small screens
          constraints: BoxConstraints(maxWidth: screenWidth * 0.36),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  DateFormat('MMM dd').format(expense.createdAt),
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (paymentUrl != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  width: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.open_in_new, size: 20),
                    tooltip: 'Open payment app',
                    onPressed: () async {
                      final uri = Uri.tryParse(paymentUrl!);
                      if (uri == null) return;
                      try {
                        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                          // ignore: avoid_print
                          print('Could not launch payment url: $paymentUrl');
                        }
                      } catch (e) {
                        // ignore: avoid_print
                        print('Error launching payment url: $e');
                      }
                    },
                  ),
                ),
              ]
            ],
          ),
        ),
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

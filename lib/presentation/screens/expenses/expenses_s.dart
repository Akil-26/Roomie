import 'package:flutter/material.dart';
import 'package:roomie/data/models/expense_model.dart';
import 'package:roomie/data/datasources/expense_service.dart';
import 'package:roomie/presentation/widgets/expense_card.dart';

class ExpensesScreen extends StatefulWidget {
  final String groupId;

  const ExpensesScreen({super.key, required this.groupId});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final ExpenseService _expenseService = ExpenseService();
  List<ExpenseModel> _expenses = [];
  Map<String, dynamic> _summary = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    try {
      final expenses =
          await _expenseService.getGroupExpenses(widget.groupId).first;
      final summary = await _expenseService.getExpensesSummary(widget.groupId);

      if (mounted) {
        setState(() {
          _expenses = expenses;
          _summary = summary;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading expenses: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body:
          _isLoading
              ? Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              )
              : Column(
                children: [
                  if (_summary.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.all(screenWidth * 0.04),
                      child: ExpenseSummaryCard(summary: _summary),
                    ),
                  Expanded(
                    child:
                        _expenses.isEmpty
                            ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.receipt_long, size: screenWidth * 0.16, color: colorScheme.onSurfaceVariant),
                                  SizedBox(height: screenHeight * 0.02),
                                  Text('No expenses yet', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            )
                            : ListView.builder(
                              padding: EdgeInsets.all(screenWidth * 0.03),
                              itemCount: _expenses.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: EdgeInsets.only(bottom: screenHeight * 0.01),
                                  child: ExpenseCard(expense: _expenses[index]),
                                );
                              },
                            ),
                  ),
                ],
              ),
    );
  }
}

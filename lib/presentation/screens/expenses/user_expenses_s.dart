import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/expense_service.dart';
import 'package:roomie/data/datasources/sms_transaction_service.dart';
import 'package:roomie/data/models/expense_model.dart';
import 'package:roomie/data/models/sms_transaction_model.dart';
import 'package:roomie/presentation/widgets/expense_card.dart';
import 'package:roomie/presentation/widgets/roomie_loading_widget.dart';
import 'package:roomie/data/datasources/local_sms_transaction_store.dart';

class UserExpensesScreen extends StatefulWidget {
  const UserExpensesScreen({super.key});

  @override
  State<UserExpensesScreen> createState() => _UserExpensesScreenState();
}

class _UserExpensesScreenState extends State<UserExpensesScreen> with SingleTickerProviderStateMixin {
  final ExpenseService _expenseService = ExpenseService();
  final SmsTransactionService _smsService = SmsTransactionService();
  
  List<ExpenseModel> _expenses = [];
  List<SmsTransactionModel> _smsTransactions = [];
  
  bool _isLoadingExpenses = true;
  bool _isLoadingSms = true;
  bool _isSyncing = false;
  bool _hasSmsPermission = false;
  bool _autoSyncAttempted = false; // prevent infinite auto-sync loops
  DateTime? _lastManualSyncAt; // debounce manual sync

  // Pagination for SMS tab
  final ScrollController _smsScrollController = ScrollController();
  static const int _smsPageSize = 100;
  int _smsOffset = 0;
  bool _smsHasMore = true;
  List<SmsTransactionModel> _visibleSmsTransactions = [];
  
  double _totalSpent = 0.0; // You paid (from group expenses)
  double _totalReceived = 0.0; // Others paid you (from group expenses)
  double _smsDebit = 0.0; // SMS tracked spending
  double _smsCredit = 0.0; // SMS tracked income
  
  late TabController _tabController;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
    _smsScrollController.addListener(_onSmsScroll);
    _checkSmsPermission();
    _loadUserExpenses();
    _loadSmsTransactions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _smsScrollController.dispose();
    super.dispose();
  }

  Future<void> _checkSmsPermission() async {
    final hasPermission = await _smsService.hasSmsPermission();
    if (mounted) {
      setState(() => _hasSmsPermission = hasPermission);
    }
  }

  Future<void> _requestSmsPermission() async {
    // Open app settings to allow user to enable SMS permission
    await openAppSettings();
    
    // Check permission status after user returns
    Future.delayed(const Duration(milliseconds: 500), () async {
      if (mounted) {
        await _checkSmsPermission();
        if (_hasSmsPermission) {
          _syncSmsTransactions();
        }
      }
    });
  }

  Future<void> _syncSmsTransactions() async {
    // Debounce: avoid rapid repeated calls within 3 seconds
    final now = DateTime.now();
    if (_lastManualSyncAt != null && now.difference(_lastManualSyncAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastManualSyncAt = now;
    if (!_hasSmsPermission) {
      _requestSmsPermission();
      return;
    }

    setState(() => _isSyncing = true);

    try {
      // Sync SMS from last 365 days to capture more history
      final fromDate = DateTime.now().subtract(const Duration(days: 365));
      final count = await _smsService.syncSmsTransactions(fromDate: fromDate);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Synced $count transactions from SMS'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Immediately refresh view from local store to show data without waiting for stream
        try {
          final authService = Provider.of<AuthService>(context, listen: false);
          final currentUser = authService.currentUser;
          if (currentUser != null) {
            final localList = LocalSmsTransactionStore().getUser(currentUser.uid);
            double debit = 0.0;
            double credit = 0.0;
            for (final txn in localList) {
              if (txn.type == TransactionType.debit) {
                debit += txn.amount;
              } else {
                credit += txn.amount;
              }
            }
            setState(() {
              _smsTransactions = localList;
              _smsDebit = debit;
              _smsCredit = credit;
              _isLoadingSms = false;
            });
          }
        } catch (_) {}
        // Also keep the stream-based load active
        _loadSmsTransactions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to sync SMS: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _loadSmsTransactions() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      if (currentUser == null) return;

      // Fallback timeout to avoid infinite loading if stream never emits
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _isLoadingSms) {
          setState(() => _isLoadingSms = false);
        }
      });

      _smsService.getUserSmsTransactions(currentUser.uid).listen((list) {
        double debit = 0.0;
        double credit = 0.0;

        for (final txn in list) {
          if (txn.type == TransactionType.debit) {
            debit += txn.amount;
          } else {
            credit += txn.amount;
          }
        }

        if (mounted) {
          setState(() {
            _smsTransactions = list;
            _smsDebit = debit;
            _smsCredit = credit;
            _isLoadingSms = false;
            _rebuildSmsPagination(currentUser.uid);
          });
          // Auto-trigger sync ONCE if empty and not attempted yet
          if (list.isEmpty && !_isSyncing && !_autoSyncAttempted) {
            _autoSyncAttempted = true;
            _syncSmsTransactions();
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSms = false);
      }
      debugPrint('Error loading SMS transactions: $e');
    }
  }

  void _rebuildSmsPagination(String userId) {
    _smsOffset = 0;
    final firstPage = LocalSmsTransactionStore().getUserPaged(userId, offset: _smsOffset, limit: _smsPageSize);
    _visibleSmsTransactions = firstPage;
    _smsHasMore = _visibleSmsTransactions.length == _smsPageSize;
  }

  void _onSmsScroll() async {
    if (!_smsHasMore || _isLoadingSms) return;
    if (_smsScrollController.position.pixels >= _smsScrollController.position.maxScrollExtent - 100) {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      if (currentUser == null) return;
      setState(() {
        _smsOffset += _smsPageSize;
        final nextPage = LocalSmsTransactionStore().getUserPaged(currentUser.uid, offset: _smsOffset, limit: _smsPageSize);
        _visibleSmsTransactions.addAll(nextPage);
        _smsHasMore = nextPage.length == _smsPageSize;
      });
    }
  }

  Future<void> _loadUserExpenses() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      if (currentUser == null) {
        if (mounted) {
          setState(() => _isLoadingExpenses = false);
        }
        return;
      }

      // Set a timeout to prevent infinite loading
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted && _isLoadingExpenses) {
          setState(() => _isLoadingExpenses = false);
        }
      });

      // Load user expenses (SMS-based transaction expenses)
      _expenseService.getUserExpenses(currentUser.uid).listen(
        (list) {
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
              _isLoadingExpenses = false;
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() => _isLoadingExpenses = false);
            debugPrint('Stream error loading expenses: $error');
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingExpenses = false);
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
    // Use fixed paddings for consistent look across devices
    const horizontalPad = 16.0;
    const verticalPad = 12.0;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          // Custom Header
          Container(
            color: cs.surface,
            child: SafeArea(
              child: Column(
                children: [
                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: horizontalPad,
                      vertical: verticalPad,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'My Expenses',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        // Top-right refresh/sync for both tabs
                        IconButton(
                          icon: _selectedTab == 1
                              ? (_isSyncing
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: cs.primary,
                                      ),
                                    )
                                  : const Icon(Icons.sync))
                              : const Icon(Icons.refresh),
                          onPressed: (_selectedTab == 1)
                              ? (_isSyncing ? null : _syncSmsTransactions)
                              : _refreshExpenses,
                          tooltip: _selectedTab == 1 ? 'Sync SMS Transactions' : 'Refresh Expenses',
                          color: cs.onSurface,
                        ),
                      ],
                    ),
                  ),
                  // Custom Tab Buttons
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: horizontalPad,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildCustomTab(
                            label: 'Roomie expence',
                            isSelected: _selectedTab == 0,
                            onTap: () {
                              _tabController.animateTo(0);
                              setState(() => _selectedTab = 0);
                            },
                            cs: cs,
                            theme: theme,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildCustomTab(
                            label: 'SMS Transactions',
                            isSelected: _selectedTab == 1,
                            onTap: () {
                              _tabController.animateTo(1);
                              setState(() => _selectedTab = 1);
                            },
                            cs: cs,
                            theme: theme,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGroupExpensesTab(theme, cs),
                _buildSmsTransactionsTab(theme, cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Refresh expenses in Roomie tab without creating extra stream subscriptions
  Future<void> _refreshExpenses() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      if (currentUser == null) return;

      setState(() => _isLoadingExpenses = true);

      final list = await _expenseService.getUserExpenses(currentUser.uid).first;
      double spent = 0.0;
      double received = 0.0;
      for (final exp in list) {
        final myShare = exp.splitAmounts[currentUser.uid] ?? 0.0;
        final iPaid = exp.paymentStatus[currentUser.uid] == true;
        if (iPaid) spent += myShare;

        if (exp.createdBy == currentUser.uid) {
          for (final p in exp.participants) {
            if (p == currentUser.uid) continue;
            final pPaid = exp.paymentStatus[p] == true;
            if (pPaid) received += (exp.splitAmounts[p] ?? 0.0);
          }
        }
      }

      if (mounted) {
        setState(() {
          _expenses = list;
          _totalSpent = spent;
          _totalReceived = received;
          _isLoadingExpenses = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expenses refreshed')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingExpenses = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh: $e')),
        );
      }
    }
  }

  Widget _buildCustomTab({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme cs,
    required ThemeData theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupExpensesTab(ThemeData theme, ColorScheme cs) {
    // Show loading while fetching expenses
    if (_isLoadingExpenses) {
      return const Center(
        child: RoomieLoadingWidget(
          size: 80,
          text: 'Loading expenses...',
          showText: true,
        ),
      );
    }
    
    // Show empty state when there are no group/roomie expenses
    if (_expenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 80,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No expenses yet',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start tracking your Roomie expenses',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: _UserExpenseSummary(
            totalSpent: _totalSpent,
            totalReceived: _totalReceived,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: _expenses.length,
            itemBuilder: (context, index) {
              final exp = _expenses[index];
              // Try to extract a payment link from metadata if present
              String? paymentLink;
              if (exp.metadata != null) {
                final md = exp.metadata!;
                if (md['paymentUrl'] != null) {
                  paymentLink = md['paymentUrl']?.toString();
                } else if (md['deeplink'] != null) {
                  paymentLink = md['deeplink']?.toString();
                } else if (md['deepLink'] != null) {
                  paymentLink = md['deepLink']?.toString();
                } else if (md['payment_link'] != null) {
                  paymentLink = md['payment_link']?.toString();
                }
              }

              return ExpenseCard(expense: exp, paymentUrl: paymentLink);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSmsTransactionsTab(ThemeData theme, ColorScheme cs) {
    // Show loading while checking permission and fetching data
    if (_isLoadingSms) {
      return const Center(
        child: RoomieLoadingWidget(
          size: 80,
          text: 'Loading transactions...',
          showText: true,
        ),
      );
    }
    
    if (!_hasSmsPermission) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sms_outlined, size: 64, color: cs.onSurfaceVariant),
              const SizedBox(height: 24),
              Text(
                'SMS Permission Required',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Please enable SMS permission from your device settings to automatically track transactions from bank messages.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _requestSmsPermission,
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: _SmsExpenseSummary(
            totalDebit: _smsDebit,
            totalCredit: _smsCredit,
          ),
        ),
        if (_smsTransactions.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 64, color: cs.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    'No SMS transactions found',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap sync to scan your messages',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _syncSmsTransactions,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync Now'),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              controller: _smsScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: _visibleSmsTransactions.length + (_smsHasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (_smsHasMore && index == _visibleSmsTransactions.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                      ),
                    ),
                  );
                }
                return _SmsTransactionCard(transaction: _visibleSmsTransactions[index]);
              },
            ),
          ),
      ],
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
              icon: Icons.trending_down,
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
              icon: Icons.trending_up,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Chip(
                  label: Text(
                    'Net ${net >= 0 ? '+' : ''}${net.toStringAsFixed(2)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: net >= 0 ? cs.onPrimaryContainer : cs.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: net >= 0 ? cs.primaryContainer : cs.errorContainer,
                ),
              ),
            ),
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

// SMS Expense Summary Widget
class _SmsExpenseSummary extends StatelessWidget {
  final double totalDebit;
  final double totalCredit;

  const _SmsExpenseSummary({
    required this.totalDebit,
    required this.totalCredit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final net = totalCredit - totalDebit;

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
              value: totalDebit,
              valueColor: cs.error,
              icon: Icons.trending_down,
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
              value: totalCredit,
              valueColor: cs.primary,
              icon: Icons.trending_up,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Chip(
                  label: Text(
                    'Net ${net >= 0 ? '+' : ''}₹${net.toStringAsFixed(2)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: net >= 0 ? cs.onPrimaryContainer : cs.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: net >= 0 ? cs.primaryContainer : cs.errorContainer,
                ),
              ),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: valueColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: valueColor, size: 16),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                Text(
                  '₹${value.toStringAsFixed(2)}',
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// SMS Transaction Card Widget
class _SmsTransactionCard extends StatelessWidget {
  final SmsTransactionModel transaction;

  const _SmsTransactionCard({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDebit = transaction.type == TransactionType.debit;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showTransactionDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isDebit ? cs.error : cs.primary),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isDebit ? Icons.trending_down : Icons.trending_up,
                  color: isDebit ? cs.onError : cs.onPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          _getModeIcon(transaction.mode),
                          size: 12,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          transaction.modeDisplay,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (transaction.category != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '• ${transaction.category}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      _formatDate(transaction.timestamp),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isDebit ? '-' : '+'}₹${transaction.amount.toStringAsFixed(2)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isDebit ? cs.error : cs.primary,
                      fontWeight: FontWeight.bold,
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

  IconData _getModeIcon(TransactionMode mode) {
    switch (mode) {
      case TransactionMode.upi:
        return Icons.phone_android;
      case TransactionMode.card:
        return Icons.credit_card;
      case TransactionMode.netBanking:
        return Icons.account_balance;
      case TransactionMode.cash:
        return Icons.money;
      default:
        return Icons.payments;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _showTransactionDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _TransactionDetailsSheet(transaction: transaction),
    );
  }
}

// Transaction Details Sheet
class _TransactionDetailsSheet extends StatelessWidget {
  final SmsTransactionModel transaction;

  const _TransactionDetailsSheet({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDebit = transaction.type == TransactionType.debit;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Amount & Type
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDebit ? 'Money Sent' : 'Money Received',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${transaction.amount.toStringAsFixed(2)}',
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: isDebit ? cs.error : cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: (isDebit ? cs.error : cs.primaryContainer),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      isDebit ? Icons.trending_down : Icons.trending_up,
                      color: isDebit ? cs.onErrorContainer : cs.onPrimaryContainer,
                      size: 32,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              
              // Details
              _DetailRow(
                icon: Icons.store,
                label: 'Merchant/Payee',
                value: transaction.displayName,
              ),
              if (transaction.category != null)
                _DetailRow(
                  icon: Icons.category,
                  label: 'Category',
                  value: transaction.category!,
                ),
              _DetailRow(
                icon: Icons.payment,
                label: 'Mode',
                value: transaction.modeDisplay,
              ),
              if (transaction.bankName != null)
                _DetailRow(
                  icon: Icons.account_balance,
                  label: 'Bank',
                  value: transaction.bankName!,
                ),
              if (transaction.upiId != null)
                _DetailRow(
                  icon: Icons.link,
                  label: 'UPI ID',
                  value: transaction.upiId!,
                ),
              if (transaction.referenceNumber != null)
                _DetailRow(
                  icon: Icons.tag,
                  label: 'Reference No.',
                  value: transaction.referenceNumber!,
                ),
              _DetailRow(
                icon: Icons.calendar_today,
                label: 'Date & Time',
                value: _formatFullDate(transaction.timestamp),
              ),
              
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              
              // Raw SMS
              Text(
                'Original SMS',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  transaction.rawMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatFullDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

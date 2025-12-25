import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/sms_transaction_service.dart';
import 'package:roomie/data/models/sms_transaction_model.dart';
import 'package:roomie/presentation/widgets/roomie_loading_widget.dart';
import 'package:roomie/data/datasources/local_sms_transaction_store.dart';
import 'package:intl/intl.dart';

class UserExpensesScreen extends StatefulWidget {
  const UserExpensesScreen({super.key});

  @override
  State<UserExpensesScreen> createState() => _UserExpensesScreenState();
}

class _UserExpensesScreenState extends State<UserExpensesScreen> {
  final SmsTransactionService _smsService = SmsTransactionService();
  
  List<SmsTransactionModel> _smsTransactions = [];
  Map<String, Map<String, List<SmsTransactionModel>>> _groupedTransactions = {};
  
  bool _isLoadingSms = true;
  bool _isSyncing = false;
  bool _hasSmsPermission = false;
  bool _permissionAskedBefore = false;
  DateTime _selectedMonth = DateTime.now();
  
  double _smsDebit = 0.0;
  double _smsCredit = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
    
    // Safety timeout - stop loading after 10 seconds max
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isLoadingSms) {
        debugPrint('⚠️ Loading timeout - forcing stop');
        setState(() => _isLoadingSms = false);
      }
    });
  }

  Future<void> _initializeScreen() async {
    try {
      await _loadPermissionStatus();
      if (_hasSmsPermission) {
        await _loadCurrentMonthSms();
      } else if (!_permissionAskedBefore) {
        // First time - show permission screen (don't auto-open settings)
        if (mounted) setState(() => _isLoadingSms = false);
      } else {
        // Permission denied before, show permission screen
        if (mounted) setState(() => _isLoadingSms = false);
      }
    } catch (e) {
      debugPrint('Error initializing expense screen: $e');
      if (mounted) setState(() => _isLoadingSms = false);
    }
  }

  Future<void> _loadPermissionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final permissionAsked = prefs.getBool('sms_permission_asked') ?? false;
    final hasPermission = await _smsService.hasSmsPermission();
    
    if (mounted) {
      setState(() {
        _hasSmsPermission = hasPermission;
        _permissionAskedBefore = permissionAsked;
      });
    }
  }

  Future<void> _savePermissionAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sms_permission_asked', true);
    setState(() => _permissionAskedBefore = true);
  }

  Future<void> _requestSmsPermission() async {
    debugPrint('🔐 Requesting SMS permission...');
    await _savePermissionAsked();
    
    // Request SMS permission directly
    try {
      final granted = await _smsService.requestSmsPermission();
      debugPrint('🔐 Permission result: $granted');
      
      if (mounted) {
        setState(() => _hasSmsPermission = granted);
        
        if (granted) {
          await _syncAndLoadSms();
        } else {
          // Permission denied - show snackbar with option to open settings
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('SMS permission denied'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () async {
                  final opened = await openAppSettings();
                  debugPrint('Settings opened: $opened');
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('🔐 Permission error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _syncAndLoadSms() async {
    if (!_hasSmsPermission || _isSyncing) return;
    
    debugPrint('🔄 Syncing SMS transactions...');
    setState(() => _isSyncing = true);
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      if (currentUser == null) {
        setState(() => _isSyncing = false);
        return;
      }

      await _smsService.syncSmsTransactions();
      await _loadCurrentMonthSms();
      
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ SMS transactions synced'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        debugPrint('Sync error: $e');
      }
    }
  }

  Future<void> _loadCurrentMonthSms() async {
    await _loadSmsForMonth(_selectedMonth);
  }

  Future<void> _loadSmsForMonth(DateTime month) async {
    debugPrint('📅 Loading SMS for month: ${DateFormat('MMMM yyyy').format(month)}');
    setState(() => _isLoadingSms = true);
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      if (currentUser == null) {
        setState(() => _isLoadingSms = false);
        return;
      }

      // Get all transactions for user
      final allTransactions = LocalSmsTransactionStore().getUser(currentUser.uid);
      
      // Filter by selected month
      final startOfMonth = DateTime(month.year, month.month, 1);
      final endOfMonth = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
      
      final monthTransactions = allTransactions.where((txn) {
        return txn.timestamp.isAfter(startOfMonth) && 
               txn.timestamp.isBefore(endOfMonth);
      }).toList();
      
      // Sort by date descending
      monthTransactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      // Group by date
      final grouped = _groupTransactionsByDate(monthTransactions);
      
      // Calculate totals
      double debit = 0.0;
      double credit = 0.0;
      for (final txn in monthTransactions) {
        if (txn.type == TransactionType.debit) {
          debit += txn.amount;
        } else {
          credit += txn.amount;
        }
      }
      
      if (mounted) {
        setState(() {
          _smsTransactions = monthTransactions;
          _groupedTransactions = grouped;
          _smsDebit = debit;
          _smsCredit = credit;
          _selectedMonth = month;
          _isLoadingSms = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSms = false);
        debugPrint('Error loading SMS: $e');
      }
    }
  }

  Map<String, Map<String, List<SmsTransactionModel>>> _groupTransactionsByDate(
    List<SmsTransactionModel> transactions,
  ) {
    final Map<String, Map<String, List<SmsTransactionModel>>> grouped = {};
    
    for (final txn in transactions) {
      // Month key (e.g., "December 2025")
      final monthKey = DateFormat('MMMM yyyy').format(txn.timestamp);
      
      // Date key (e.g., "25 Dec, Thu")
      final dateKey = DateFormat('d MMM, EEE').format(txn.timestamp);
      
      grouped.putIfAbsent(monthKey, () => {});
      grouped[monthKey]!.putIfAbsent(dateKey, () => []);
      grouped[monthKey]![dateKey]!.add(txn);
    }
    
    return grouped;
  }

  void _showMonthPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final now = DateTime.now();
        final months = List.generate(12, (index) {
          return DateTime(now.year, now.month - index, 1);
        });
        
        return Container(
          padding: const EdgeInsets.all(16),
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Month',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: months.length,
                  itemBuilder: (context, index) {
                    final month = months[index];
                    final isSelected = month.year == _selectedMonth.year &&
                        month.month == _selectedMonth.month;
                    
                    return ListTile(
                      title: Text(
                        DateFormat('MMMM yyyy').format(month),
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: isSelected ? const Icon(Icons.check_circle) : null,
                      selected: isSelected,
                      onTap: () {
                        Navigator.pop(context);
                        _loadSmsForMonth(month);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          // Header
          Container(
            color: cs.surface,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Expenses',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_hasSmsPermission)
                            Text(
                              DateFormat('MMMM yyyy').format(_selectedMonth),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_hasSmsPermission) ...[
                      // Sync button
                      IconButton(
                        icon: _isSyncing
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.primary,
                                ),
                              )
                            : const Icon(Icons.sync),
                        onPressed: _isSyncing ? null : _syncAndLoadSms,
                        tooltip: 'Sync SMS',
                      ),
                      // Month selector
                      IconButton(
                        icon: const Icon(Icons.calendar_month),
                        onPressed: _showMonthPicker,
                        tooltip: 'Select Month',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Summary Card - Always visible at top when permission granted
          if (_hasSmsPermission && !_isLoadingSms)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primaryContainer, cs.secondaryContainer],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSummaryItem(
                      icon: Icons.trending_down,
                      label: 'Spent',
                      amount: _smsDebit,
                      color: Colors.red,
                      theme: theme,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: cs.outline.withOpacity(0.3),
                  ),
                  Expanded(
                    child: _buildSummaryItem(
                      icon: Icons.trending_up,
                      label: 'Received',
                      amount: _smsCredit,
                      color: Colors.green,
                      theme: theme,
                    ),
                  ),
                ],
              ),
            ),
          // Content
          Expanded(
            child: _buildContent(theme, cs),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, ColorScheme cs) {
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
      return _buildPermissionScreen(theme, cs);
    }
    
    if (_smsTransactions.isEmpty) {
      return _buildEmptyState(theme, cs);
    }
    
    return _buildTransactionsList(theme, cs);
  }

  Widget _buildPermissionScreen(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sms_outlined, size: 80, color: cs.onSurfaceVariant),
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
              'Allow SMS access to automatically track your bank transactions and expenses.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _requestSmsPermission,
              icon: const Icon(Icons.lock_open),
              label: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 80,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions this month',
            style: theme.textTheme.titleLarge?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your SMS transactions will appear here',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList(ThemeData theme, ColorScheme cs) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _groupedTransactions[DateFormat('MMMM yyyy').format(_selectedMonth)]?.length ?? 0,
      itemBuilder: (context, index) {
        final monthData = _groupedTransactions[DateFormat('MMMM yyyy').format(_selectedMonth)]!;
        final dateKey = monthData.keys.elementAt(index);
        final transactions = monthData[dateKey]!;
        
        return _buildDateGroup(dateKey, transactions, theme, cs);
      },
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required double amount,
    required Color color,
    required ThemeData theme,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildDateGroup(
    String dateKey,
    List<SmsTransactionModel> transactions,
    ThemeData theme,
    ColorScheme cs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Text(
            dateKey,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
        ),
        // Transactions for this date
        ...transactions.map((txn) => _buildTransactionTile(txn, theme, cs)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTransactionTile(
    SmsTransactionModel txn,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final isDebit = txn.type == TransactionType.debit;
    final color = isDebit ? Colors.red : Colors.green;
    
    return GestureDetector(
      onTap: () => _showTransactionDetails(txn, theme, cs),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outline.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            // Icon - Trading style
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isDebit ? Icons.trending_down : Icons.trending_up,
                color: color,
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
                    txn.merchantName ?? 'Transaction',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (txn.bankName != null)
                    Text(
                      txn.bankName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            // Amount
            Text(
              '${isDebit ? '-' : '+'}₹${txn.amount.toStringAsFixed(2)}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }

  void _showTransactionDetails(
    SmsTransactionModel txn,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final isDebit = txn.type == TransactionType.debit;
    final color = isDebit ? Colors.red : Colors.green;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isDebit ? Icons.trending_down : Icons.trending_up,
                      color: color,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isDebit ? 'Money Sent' : 'Money Received',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          DateFormat('EEEE, d MMMM yyyy • hh:mm a').format(txn.timestamp),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Amount
              Center(
                child: Text(
                  '${isDebit ? '-' : '+'}₹${txn.amount.toStringAsFixed(2)}',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Details
              _buildDetailRow('Merchant', txn.merchantName ?? 'Unknown', theme, cs),
              _buildDetailRow('Bank', txn.bankName ?? 'Unknown', theme, cs),
              _buildDetailRow('Type', isDebit ? 'Debit (Spent)' : 'Credit (Received)', theme, cs),
              _buildDetailRow('Date', DateFormat('d MMM yyyy').format(txn.timestamp), theme, cs),
              _buildDetailRow('Time', DateFormat('hh:mm a').format(txn.timestamp), theme, cs),
              
              const SizedBox(height: 16),
              
              // Close button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

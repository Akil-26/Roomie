import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:roomie/data/datasources/groups_service.dart';
import 'package:roomie/data/datasources/room_payment_service.dart';
import 'package:roomie/presentation/widgets/action_guard.dart';

/// STEP-7: Owner Dashboard - Visibility & Controls
/// 
/// Purpose: Give owner reasons to use the app beyond "just rent"
/// - Control: Room visibility toggle
/// - Visibility: Stats at a glance
/// - Confidence: Room health indicators
/// 
/// RULES:
/// - READ-ONLY insights (no auto-actions)
/// - Owner-only features
/// - No roommate privacy intrusion
/// - No analytics/notifications/reminders

/// Owner dashboard stats model
class OwnerDashboardStats {
  final int totalRoommates;
  final int maxCapacity;
  final int pendingJoinRequests;
  final double totalPaymentsReceived;
  final String currency;
  final DateTime? lastPaymentDate;
  final bool isRoomPublic;
  final List<String> paidUserIds;
  final List<String> allMemberIds;

  OwnerDashboardStats({
    required this.totalRoommates,
    required this.maxCapacity,
    required this.pendingJoinRequests,
    required this.totalPaymentsReceived,
    required this.currency,
    this.lastPaymentDate,
    required this.isRoomPublic,
    required this.paidUserIds,
    required this.allMemberIds,
  });

  /// Room health status based on occupancy and requests
  RoomHealthStatus get healthStatus {
    if (totalRoommates >= maxCapacity) {
      return RoomHealthStatus.fullyOccupied;
    } else if (pendingJoinRequests > 0) {
      return RoomHealthStatus.pendingRequests;
    } else {
      return RoomHealthStatus.vacancyAvailable;
    }
  }

  /// Get members who haven't paid this month
  List<String> get unpaidMemberIds {
    return allMemberIds.where((id) => !paidUserIds.contains(id)).toList();
  }
}

enum RoomHealthStatus {
  fullyOccupied,
  vacancyAvailable,
  pendingRequests,
}

/// STEP-7: Owner Dashboard Widget
/// 
/// Shows:
/// - Room stats (roommates, requests)
/// - Payment summary
/// - Room health indicator
/// - Room visibility toggle (only control)
class OwnerDashboardWidget extends StatefulWidget {
  final String roomId;
  final String roomName;
  final VoidCallback? onVisibilityChanged;

  const OwnerDashboardWidget({
    super.key,
    required this.roomId,
    required this.roomName,
    this.onVisibilityChanged,
  });

  @override
  State<OwnerDashboardWidget> createState() => _OwnerDashboardWidgetState();
}

class _OwnerDashboardWidgetState extends State<OwnerDashboardWidget>
    with ActionGuardMixin {
  final GroupsService _groupsService = GroupsService();
  final RoomPaymentService _paymentService = RoomPaymentService();

  bool _isLoading = true;
  OwnerDashboardStats? _stats;

  @override
  void initState() {
    super.initState();
    _loadDashboardStats();
  }

  Future<void> _loadDashboardStats() async {
    setState(() => _isLoading = true);

    try {
      // Get room details
      final roomDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.roomId)
          .get();

      if (!roomDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      final roomData = roomDoc.data()!;
      final maxCapacity = roomData['maxMembers'] ?? roomData['capacity'] ?? 4;
      final isPublic = roomData['isPublic'] ?? true;
      final currency = roomData['rentCurrency'] ?? 'INR';

      // Get room members count
      final members = await _groupsService.getRoomMembers(widget.roomId);
      final memberIds = members.map((m) => m.userId).toList();

      // Get pending join requests count
      final pendingRequests = await _groupsService.getPendingJoinRequests(widget.roomId);

      // Get payment summary
      final paymentSummary = await _paymentService.getRoomPaymentSummary(widget.roomId);
      
      // Get all-time payments for total
      final allPayments = await _paymentService.getRoomPayments(widget.roomId);
      double totalReceived = 0;
      DateTime? lastPayment;
      
      for (final payment in allPayments) {
        if (payment.status.value == 'success') {
          totalReceived += payment.amount;
          if (lastPayment == null || payment.createdAt.isAfter(lastPayment)) {
            lastPayment = payment.createdAt;
          }
        }
      }

      final paidUserIds = List<String>.from(paymentSummary['paidUserIds'] ?? []);

      if (mounted) {
        setState(() {
          _stats = OwnerDashboardStats(
            totalRoommates: members.length,
            maxCapacity: maxCapacity,
            pendingJoinRequests: pendingRequests.length,
            totalPaymentsReceived: totalReceived,
            currency: currency,
            lastPaymentDate: lastPayment,
            isRoomPublic: isPublic,
            paidUserIds: paidUserIds,
            allMemberIds: memberIds,
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading owner dashboard: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleRoomVisibility() async {
    if (_stats == null) return;

    final newVisibility = !_stats!.isRoomPublic;
    
    // STEP-6: Double-action protection
    await guardedAction<void>(
      'toggle_visibility',
      () async {
        final success = await _groupsService.setRoomVisibility(
          widget.roomId, 
          newVisibility,
        );

        if (success && mounted) {
          // Update local state
          setState(() {
            _stats = OwnerDashboardStats(
              totalRoommates: _stats!.totalRoommates,
              maxCapacity: _stats!.maxCapacity,
              pendingJoinRequests: _stats!.pendingJoinRequests,
              totalPaymentsReceived: _stats!.totalPaymentsReceived,
              currency: _stats!.currency,
              lastPaymentDate: _stats!.lastPaymentDate,
              isRoomPublic: newVisibility,
              paidUserIds: _stats!.paidUserIds,
              allMemberIds: _stats!.allMemberIds,
            );
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                newVisibility 
                    ? 'Room is now open for new join requests'
                    : 'Room is now closed to new join requests',
              ),
              backgroundColor: newVisibility ? Colors.green : Colors.orange,
            ),
          );

          widget.onVisibilityChanged?.call();
        }
      },
      onError: (e) {
        if (mounted) {
          showNetworkErrorSnackbar(context, message: 'Failed to update room visibility');
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

  String _formatAmount(double amount, String currency) {
    final symbol = _getCurrencySymbol(currency);
    if (amount >= 100000) {
      return '$symbol${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return '$symbol${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '$symbol${amount.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_stats == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(Icons.dashboard, color: colorScheme.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Owner Dashboard',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Room Health Indicator
        _buildRoomHealthCard(colorScheme, textTheme),
        const SizedBox(height: 12),

        // Stats Cards Row
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.group,
                title: 'Roommates',
                value: '${_stats!.totalRoommates}/${_stats!.maxCapacity}',
                color: Colors.blue,
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.person_add,
                title: 'Pending',
                value: '${_stats!.pendingJoinRequests}',
                subtitle: 'requests',
                color: Colors.purple,
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Payment Stats Row
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.payments,
                title: 'Total Received',
                value: _formatAmount(_stats!.totalPaymentsReceived, _stats!.currency),
                color: Colors.green,
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.schedule,
                title: 'Last Payment',
                value: _stats!.lastPaymentDate != null
                    ? DateFormat.MMMd().format(_stats!.lastPaymentDate!)
                    : 'None yet',
                color: Colors.orange,
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Room Visibility Toggle
        _buildVisibilityToggle(colorScheme, textTheme),
        const SizedBox(height: 12),

        // Payment Status (who paid/hasn't)
        if (_stats!.allMemberIds.isNotEmpty)
          _buildPaymentStatusCard(colorScheme, textTheme),
      ],
    );
  }

  /// STEP-7: Room Health Indicator Card
  Widget _buildRoomHealthCard(ColorScheme colorScheme, TextTheme textTheme) {
    final status = _stats!.healthStatus;
    
    IconData icon;
    String label;
    Color color;

    switch (status) {
      case RoomHealthStatus.fullyOccupied:
        icon = Icons.check_circle;
        label = 'Fully Occupied';
        color = Colors.green;
        break;
      case RoomHealthStatus.pendingRequests:
        icon = Icons.pending_actions;
        label = 'Pending Requests';
        color = Colors.orange;
        break;
      case RoomHealthStatus.vacancyAvailable:
        icon = Icons.door_front_door;
        label = 'Vacancy Available';
        color = Colors.blue;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Text(
            label,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            '${_stats!.totalRoommates}/${_stats!.maxCapacity} members',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// STEP-7: Stat Card Widget
  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    required Color color,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  /// STEP-7: Room Visibility Toggle
  /// Only control: open/close room to new join requests
  Widget _buildVisibilityToggle(ColorScheme colorScheme, TextTheme textTheme) {
    final isPublic = _stats!.isRoomPublic;
    final isToggling = isActionInProgress('toggle_visibility');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            isPublic ? Icons.lock_open : Icons.lock,
            color: isPublic ? Colors.green : Colors.orange,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Room Visibility',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  isPublic 
                      ? 'Open for new join requests'
                      : 'Closed to new join requests',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (isToggling)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: isPublic,
              onChanged: (_) => _toggleRoomVisibility(),
              activeColor: Colors.green,
            ),
        ],
      ),
    );
  }

  /// STEP-7: Payment Status Card (who paid / who hasn't this month)
  /// VISIBILITY: Owner sees payment status without intrusion
  Widget _buildPaymentStatusCard(ColorScheme colorScheme, TextTheme textTheme) {
    final paidCount = _stats!.paidUserIds.length;
    final totalCount = _stats!.allMemberIds.length;
    final unpaidCount = totalCount - paidCount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check, color: Colors.teal, size: 20),
              const SizedBox(width: 8),
              Text(
                'This Month\'s Payments',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildPaymentStatusChip(
                  icon: Icons.check_circle,
                  label: '$paidCount paid',
                  color: Colors.green,
                  textTheme: textTheme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPaymentStatusChip(
                  icon: Icons.schedule,
                  label: '$unpaidCount pending',
                  color: unpaidCount > 0 ? Colors.orange : Colors.grey,
                  textTheme: textTheme,
                ),
              ),
            ],
          ),
          if (unpaidCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              '* Pending payments are for roommates who haven\'t paid this month yet',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentStatusChip({
    required IconData icon,
    required String label,
    required Color color,
    required TextTheme textTheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

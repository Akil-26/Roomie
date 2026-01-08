import 'package:flutter/material.dart';
import 'package:roomie/data/datasources/groups_service.dart';
import 'package:roomie/presentation/widgets/action_guard.dart';

/// Screen for owners to view and manage join requests to their group.
/// 
/// STEP-6: Safety Guards:
/// - Double-action protection for approve/reject buttons
/// - App resume safety to refresh request list
/// - Defensive assertions for request status
class JoinRequestsScreen extends StatefulWidget {
  final Map<String, dynamic> group;

  const JoinRequestsScreen({super.key, required this.group});

  @override
  State<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends State<JoinRequestsScreen> 
    with WidgetsBindingObserver, ActionGuardMixin {
  final GroupsService _groupsService = GroupsService();

  @override
  void initState() {
    super.initState();
    // STEP-6: Register for app lifecycle events
    WidgetsBinding.instance.addObserver(this);
  }

  // STEP-6: App Background/Resume Safety
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Force rebuild to refresh stream data
      setState(() {});
    }
  }

  @override
  void dispose() {
    // STEP-6: Cleanup lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 1,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
        ),
        title: Text(
          'Join Requests',
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _groupsService.getGroupJoinRequests(widget.group['id']),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: screenWidth * 0.16, color: colorScheme.error),  // 16% icon
                  SizedBox(height: screenHeight * 0.02),  // 2% gap
                  Text(
                    'Error Loading Requests',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.01),  // 1% gap
                  Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          final requests = snapshot.data ?? [];

          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.group_off,
                    size: screenWidth * 0.16,  // 16% icon
                    color: colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(height: screenHeight * 0.02),  // 2% gap
                  Text(
                    'No Join Requests',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.01),  // 1% gap
                  Text(
                    'When people request to join your group,\\nthey\'ll appear here for approval.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(screenWidth * 0.04),  // 4% padding
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              return _buildRequestCard(request);
            },
          );
        },
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: EdgeInsets.only(bottom: screenHeight * 0.02),  // 2% margin
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.onSurfaceVariant.withAlpha(25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(screenWidth * 0.05),  // 5% padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Info Row
            Row(
              children: [
                // User Avatar
                CircleAvatar(
                  radius: screenWidth * 0.075,  // 7.5% radius
                  backgroundColor: colorScheme.primary,
                  child: Text(
                    (request['userName'] as String?)
                            ?.substring(0, 1)
                            .toUpperCase() ??
                        'U',
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: screenWidth * 0.04),  // 4% gap
                // User Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request['userName'] ?? 'Unknown User',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.005),  // 0.5% gap
                      if (request['userEmail'] != null &&
                          request['userEmail'].isNotEmpty)
                        _buildDetailRow(
                          icon: Icons.email_outlined,
                          text: request['userEmail'],
                          screenWidth: screenWidth,
                        ),
                      if (request['userAge'] != null)
                        _buildDetailRow(
                          icon: Icons.cake_outlined,
                          text: '${request['userAge']} years old',
                          screenWidth: screenWidth,
                        ),
                      if (request['userOccupation'] != null &&
                          request['userOccupation'].isNotEmpty)
                        _buildDetailRow(
                          icon: Icons.work_outline,
                          text: request['userOccupation'],
                          screenWidth: screenWidth,
                        ),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: screenHeight * 0.02),  // 2% gap

            // Request Time
            Container(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.03, vertical: screenHeight * 0.007),  // Dynamic padding
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule,
                    size: screenWidth * 0.04,  // 4% icon
                    color: colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(width: screenWidth * 0.015),  // 1.5% gap
                  Text(
                    'Requested ${_formatTimeAgo(request['requestedAt'])}',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: screenHeight * 0.025),  // 2.5% gap

            // STEP-6: Action Buttons with double-tap protection
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isActionInProgress('reject_${request['id']}')
                        ? null
                        : () => _rejectRequest(request),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(color: colorScheme.error),
                      padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),  // 1.5% vertical
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: isActionInProgress('reject_${request['id']}')
                        ? SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.error,
                            ),
                          )
                        : Text(
                      'Reject',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: screenWidth * 0.03),  // 3% gap
                Expanded(
                  child: ElevatedButton(
                    onPressed: isActionInProgress('approve_${request['id']}')
                        ? null
                        : () => _approveRequest(request),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),  // 1.5% vertical
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: isActionInProgress('approve_${request['id']}')
                        ? SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : Text(
                      'Approve',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon, 
    required String text,
    required double screenWidth,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: screenWidth * 0.01),  // 1% padding
      child: Row(
        children: [
          Icon(icon, size: screenWidth * 0.04, color: colorScheme.onSurfaceVariant),  // 4% icon
          SizedBox(width: screenWidth * 0.015),  // 1.5% gap
          Expanded(
            child: Text(
              text,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approveRequest(Map<String, dynamic> request) async {
    // STEP-6: Double-action protection with guardedAction
    await guardedAction<void>(
      'approve_${request['id']}',
      () async {
        final success = await _groupsService.approveJoinRequest(
          request['id'],
          request['groupId'],
          request['userId'],
        );

        if (success && mounted) {
          final colorScheme = Theme.of(context).colorScheme;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${request['userName']} has been added to the group!',
              ),
              backgroundColor: colorScheme.secondary,
              action: SnackBarAction(
                label: 'OK',
                textColor: colorScheme.onSecondary,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          if (mounted) Navigator.of(context).pop(); // Pop after success
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to approve request. Please try again.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      onError: (e) {
        if (mounted) {
          showNetworkErrorSnackbar(context, message: 'Failed to approve. Check your connection.');
        }
      },
    );
  }

  Future<void> _rejectRequest(Map<String, dynamic> request) async {
    // STEP-6: Double-action protection with guardedAction
    await guardedAction<void>(
      'reject_${request['id']}',
      () async {
        final success = await _groupsService.rejectJoinRequest(
          request['id'],
          request['groupId'], // Pass groupId
        );

        if (success && mounted) {
          final colorScheme = Theme.of(context).colorScheme;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Request from ${request['userName']} was rejected.'),
              backgroundColor: colorScheme.error,
            ),
          );
          if (mounted) Navigator.of(context).pop(); // Pop after success
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to reject request. Please try again.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      onError: (e) {
        if (mounted) {
          showNetworkErrorSnackbar(context, message: 'Failed to reject. Check your connection.');
        }
      },
    );
  }

  String _formatTimeAgo(dynamic timestamp) {
    if (timestamp == null) return 'unknown time';

    try {
      DateTime date;
      if (timestamp is int) {
        date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else {
        // Firestore Timestamp
        date = timestamp.toDate();
      }

      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return 'unknown time';
    }
  }
}

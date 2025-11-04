import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:roomie/data/models/notification_model.dart';
import 'package:roomie/presentation/screens/groups/join_requests_s.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/groups_service.dart';
import 'package:roomie/data/datasources/notification_service.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final notificationService = NotificationService();
    final userId = authService.currentUser?.uid;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        centerTitle: false,
      ),
      backgroundColor: colorScheme.surfaceContainerLowest,
      body:
          userId == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.login_outlined,
                        size: screenWidth * 0.2,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      Text(
                        'Please log in',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.01),
                      Text(
                        'to see notifications',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : StreamBuilder<List<NotificationModel>>(
                stream: notificationService.getNotifications(userId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: colorScheme.primary,
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: screenWidth * 0.2,
                            color: colorScheme.error,
                          ),
                          SizedBox(height: screenHeight * 0.02),
                          Text(
                            'Something went wrong',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(height: screenHeight * 0.01),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.1),
                            child: Text(
                              '${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: EdgeInsets.all(screenWidth * 0.1),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.notifications_off_outlined,
                              size: screenWidth * 0.15,
                              color: colorScheme.primary,
                            ),
                          ),
                          SizedBox(height: screenHeight * 0.03),
                          Text(
                            'No notifications yet',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(height: screenHeight * 0.01),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.15),
                            child: Text(
                              'We\'ll notify you when something new arrives',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final notifications = snapshot.data!;

                  return ListView.separated(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.04,
                      vertical: screenHeight * 0.02,
                    ),
                    itemCount: notifications.length,
                    separatorBuilder: (context, index) => SizedBox(height: screenHeight * 0.012),
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return NotificationCard(notification: notification);
                    },
                  );
                },
              ),
    );
  }
}

class NotificationCard extends StatefulWidget {
  final NotificationModel notification;

  const NotificationCard({super.key, required this.notification});

  @override
  State<NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<NotificationCard> {
  bool _isDeleted = false;

  Color _getColorForType(String type, ColorScheme colorScheme) {
    switch (type) {
      case 'group_join_conflict':
        return colorScheme.error;
      case 'request_accepted':
        return colorScheme.tertiary;
      case 'request_sent':
        return colorScheme.secondary;
      case 'join_request_received':
        return colorScheme.primary;
      default:
        return colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationService = NotificationService();
    final bool isJoinRequestNotification =
        widget.notification.type == 'join_request_received';
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final notificationColor = _getColorForType(widget.notification.type, colorScheme);

    // Don't show if marked as deleted (allows undo before actual deletion)
    if (_isDeleted) {
      return const SizedBox.shrink();
    }

    return Dismissible(
      key: Key(widget.notification.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        // Mark as deleted but don't actually delete yet
        setState(() {
          _isDeleted = true;
        });

        // Show snackbar with undo option
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Notification deleted'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: colorScheme.inverseSurface,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Undo',
              textColor: colorScheme.inversePrimary,
              onPressed: () {
                // Restore the notification
                if (mounted) {
                  setState(() {
                    _isDeleted = false;
                  });
                }
              },
            ),
          ),
        ).closed.then((reason) {
          // If snackbar was dismissed without undo, actually delete from database
          if (reason != SnackBarClosedReason.action && mounted) {
            notificationService.deleteNotification(widget.notification.id);
          }
        });

        // Return false to prevent automatic dismissal
        // We handle visibility with _isDeleted flag
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: screenWidth * 0.05),
        decoration: BoxDecoration(
          color: colorScheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.delete_outline,
          color: colorScheme.onError,
          size: screenWidth * 0.07,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap:
            isJoinRequestNotification
                ? () => _handleJoinRequestTap(context)
                : null,
        child: Container(
          decoration: BoxDecoration(
            color: widget.notification.isRead 
                ? colorScheme.surface 
                : colorScheme.primaryContainer.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.notification.isRead 
                  ? colorScheme.outlineVariant
                  : notificationColor.withValues(alpha: 0.3),
              width: widget.notification.isRead ? 1 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(screenWidth * 0.04),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon Avatar
                Container(
                  width: screenWidth * 0.12,
                  height: screenWidth * 0.12,
                  decoration: BoxDecoration(
                    color: notificationColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getIconForType(widget.notification.type),
                    color: notificationColor,
                    size: screenWidth * 0.06,
                  ),
                ),
                SizedBox(width: screenWidth * 0.03),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.notification.title,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (!widget.notification.isRead)
                            Container(
                              width: screenWidth * 0.025,
                              height: screenWidth * 0.025,
                              decoration: BoxDecoration(
                                color: notificationColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: screenHeight * 0.008),
                      Text(
                        widget.notification.body,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.01),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: screenWidth * 0.035,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          SizedBox(width: screenWidth * 0.01),
                          Text(
                            timeago.format(widget.notification.createdAt.toDate()),
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      // Action Buttons
                      if (widget.notification.type == 'group_join_conflict' ||
                          widget.notification.type == 'join_request_received') ...[
                        SizedBox(height: screenHeight * 0.015),
                        _buildActionButtons(context, notificationService, notificationColor),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    NotificationService notificationService,
    Color accentColor,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    if (widget.notification.type == 'group_join_conflict') {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                await notificationService.deleteNotification(widget.notification.id);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.onSurface,
                side: BorderSide(color: colorScheme.outline),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.012),
              ),
              child: const Text('Cancel'),
            ),
          ),
          SizedBox(width: screenWidth * 0.03),
          Expanded(
            child: FilledButton(
              onPressed: () => _handleSwitchGroup(context, widget.notification),
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.012),
              ),
              child: const Text('Switch'),
            ),
          ),
        ],
      );
    } else if (widget.notification.type == 'join_request_received') {
      return FilledButton.icon(
        onPressed: () => _handleJoinRequestTap(context),
        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        label: const Text('Review Request'),
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.04,
            vertical: screenHeight * 0.012,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _handleSwitchGroup(
    BuildContext context,
    NotificationModel notification,
  ) async {
    final groupsService = GroupsService();
    final notificationService = NotificationService();
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Leave Current Group?'),
            content: const Text(
              'Are you sure you want to leave your current group and join this new one?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        final String newGroupId = notification.data['newGroupId'];
        final String currentGroupId = notification.data['currentGroupId'];
        final String userId = notification.userId;

        await groupsService.switchGroup(
          userId: userId,
          currentGroupId: currentGroupId,
          newGroupId: newGroupId,
        );
        await notificationService.deleteNotification(notification.id);

        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Successfully switched groups!',
              style: TextStyle(color: colorScheme.onPrimary),
            ),
            backgroundColor: colorScheme.primary,
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Failed to switch groups: $e',
              style: TextStyle(color: colorScheme.onError),
            ),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'group_join_conflict':
        return Icons.merge_type;
      case 'request_accepted':
        return Icons.check_circle_outline;
      case 'request_sent':
        return Icons.send_outlined;
      case 'join_request_received':
        return Icons.person_add_alt_1_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Future<void> _handleJoinRequestTap(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final colorScheme = Theme.of(context).colorScheme;

    final groupId = widget.notification.data['groupId'] as String?;
    if (groupId == null || groupId.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Group information is missing for this request.'),
        ),
      );
      return;
    }

    var dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final group = await GroupsService().getGroupById(groupId);

      if (dialogOpen) {
        rootNavigator.pop();
        dialogOpen = false;
      }

      if (group == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('The group could not be found.')),
        );
        return;
      }

      if (!widget.notification.isRead) {
        await NotificationService().markAsRead(widget.notification.id);
      }

      navigator.push(
        MaterialPageRoute(builder: (_) => JoinRequestsScreen(group: group)),
      );
    } catch (e) {
      if (dialogOpen) {
        rootNavigator.pop();
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to open join requests: $e',
            style: TextStyle(color: colorScheme.onError),
          ),
          backgroundColor: colorScheme.error,
        ),
      );
    }
  }
}

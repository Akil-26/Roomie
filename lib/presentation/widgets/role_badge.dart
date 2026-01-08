import 'package:flutter/material.dart';

/// Role types for room members
enum RoomRole {
  owner,
  roommate,
  pending,
}

/// A reusable badge widget to display user roles clearly.
/// 
/// STEP-5: UX & Trust Polish - Clear Role Labels
/// - Owner → badge: "Owner / Manager"
/// - Roommate → badge: "Roommate"
/// - Pending user → "Join request pending"
/// 
/// Owner must never appear in Members list.
class RoleBadge extends StatelessWidget {
  final RoomRole role;
  final bool compact;

  const RoleBadge({
    super.key,
    required this.role,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Color backgroundColor;
    Color textColor;
    IconData icon;
    String label;

    switch (role) {
      case RoomRole.owner:
        backgroundColor = Colors.blue.withAlpha(30);
        textColor = Colors.blue;
        icon = Icons.verified_user;
        label = compact ? 'Owner' : 'Owner / Manager';
        break;
      case RoomRole.roommate:
        backgroundColor = Colors.green.withAlpha(30);
        textColor = Colors.green;
        icon = Icons.person;
        label = 'Roommate';
        break;
      case RoomRole.pending:
        backgroundColor = Colors.orange.withAlpha(30);
        textColor = Colors.orange;
        icon = Icons.hourglass_empty;
        label = compact ? 'Pending' : 'Join request pending';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: textColor),
          SizedBox(width: compact ? 4 : 6),
          Text(
            label,
            style: (textTheme.labelSmall ?? const TextStyle(fontSize: 12)).copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 10 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// A status indicator for join request status.
/// 
/// STEP-5: Trust Builder - Clear pending state indication.
class JoinRequestStatusBadge extends StatelessWidget {
  final String status; // 'pending', 'approved', 'rejected'

  const JoinRequestStatusBadge({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    IconData icon;
    String label;

    switch (status.toLowerCase()) {
      case 'pending':
        backgroundColor = Colors.orange.withAlpha(30);
        textColor = Colors.orange;
        icon = Icons.hourglass_empty;
        label = 'Pending Approval';
        break;
      case 'approved':
        backgroundColor = Colors.green.withAlpha(30);
        textColor = Colors.green;
        icon = Icons.check_circle;
        label = 'Approved';
        break;
      case 'rejected':
        backgroundColor = Colors.red.withAlpha(30);
        textColor = Colors.red;
        icon = Icons.cancel;
        label = 'Rejected';
        break;
      default:
        backgroundColor = Colors.grey.withAlpha(30);
        textColor = Colors.grey;
        icon = Icons.help_outline;
        label = 'Unknown';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

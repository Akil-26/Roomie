import 'package:flutter/material.dart';
import 'package:roomie/data/datasources/auth_service.dart';

class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ElevatedButton.icon(
      onPressed: () async {
        final bool? confirmLogout = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(
                'Logout',
                style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                  color: Theme.of(dialogContext).colorScheme.onSurface,
                ),
              ),
              content: Text(
                'Are you sure you want to logout?',
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color:
                          Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(
                    'Logout',
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ),
              ],
            );
          },
        );

        if (confirmLogout == true) {
          try {
            await AuthService().signOut();
            if (context.mounted) {
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/', (route) => false);
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Logout failed: $e'),
                  backgroundColor: colorScheme.error,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        }
      },
      icon: Icon(Icons.logout, color: colorScheme.onError),
      label: Text('Logout', style: TextStyle(color: colorScheme.onError)),
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.error,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

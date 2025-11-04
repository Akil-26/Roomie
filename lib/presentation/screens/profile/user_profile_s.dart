// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import 'package:roomie/data/models/user_model.dart';
import 'package:roomie/presentation/screens/profile/edit_profile_s.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/firestore_service.dart';
import 'package:roomie/data/datasources/profile_image_notifier.dart';
import 'package:roomie/presentation/widgets/profile_image_widget.dart';
import 'package:roomie/presentation/screens/expenses/user_expenses_s.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final ProfileImageNotifier _profileImageNotifier = ProfileImageNotifier();
  UserModel? _currentUser;
  bool _isLoading = true;
  int _followersCount = 0;
  int _followingCount = 0;
  // Legacy Mongo widget removed; key no longer required.

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    print('Profile: Loading user data...'); // Debug log
    try {
      final user = _authService.currentUser;
      print(
        'Profile: Current user: ${user?.uid} - ${user?.email}',
      ); // Debug log
      if (user != null) {
        final userData = await _firestoreService.getUserDetails(user.uid);
        print('Profile: Raw user data from Firestore: $userData'); // Debug log
        if (userData != null) {
          print(
            'Profile: User data loaded: ${userData['profileImageUrl']}',
          ); // Debug log
          setState(() {
            _currentUser = UserModel.fromMap(userData, user.uid);
            _isLoading = false;
          });

          // Load follower/following counts
          _loadFollowCounts();

          // Update global profile image state
          _profileImageNotifier.updateProfileImage(userData['profileImageUrl']);
        } else {
          // No Firestore data - user needs to complete profile
          print(
            'Profile: No user data found in Firestore - need to complete profile',
          ); // Debug log
          setState(() {
            _currentUser = UserModel(
              uid: user.uid,
              email: user.email ?? '',
              // Don't use displayName from Auth - use username from Firestore
              username: null, // Will show email prefix as fallback
              phone: user.phoneNumber,
              profileImageUrl: user.photoURL,
            );
            _isLoading = false;
          });
          _loadFollowCounts();
          // Also seed notifier with Google photoURL if present
          if (user.photoURL != null) {
            _profileImageNotifier.updateProfileImage(user.photoURL!);
          }
        }
      } else {
        print('Profile: No authenticated user found'); // Debug log
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Profile: Error loading user data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if user is authenticated
    if (_authService.currentUser == null) {
      print('Profile: User not authenticated, redirecting to login');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/');
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Profile',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              letterSpacing: -0.015,
            ),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    if (_currentUser == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Profile',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              letterSpacing: -0.015,
            ),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_off,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              SizedBox(height: 16),
              Text(
                'No user data found',
                style: TextStyle(
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Profile',
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.015,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.edit, color: colorScheme.primary),
            onPressed: () async {
              if (_currentUser != null) {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) =>
                            EditProfileScreen(currentUser: _currentUser!),
                  ),
                );

                // Reload user data if profile was updated
                if (result is Map) {
                  // Optimistic update if we received new URL back
                  final newUrl = result['profileImageUrl'] as String?;
                  if (newUrl != null && newUrl.isNotEmpty) {
                    print('Optimistically updating profile image to $newUrl');
                    _profileImageNotifier.updateProfileImage(newUrl);
                    setState(() {
                      _currentUser = _currentUser!.copyWith(
                        profileImageUrl: newUrl,
                      );
                    });
                  }
                  _loadUserData(); // still refetch to ensure consistency
                } else if (result == true) {
                  // Backward compatibility if we just returned true
                  _loadUserData();
                }
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Header Card (Profile picture + name + bio)
            Padding(
              padding: EdgeInsets.all(screenWidth * 0.02),  // 2% gap on all sides
              child: _buildHeaderCard(),
            ),

            const SizedBox(height: 24),

            // Followers / Following stats
            Padding(
              padding: EdgeInsets.all(screenWidth * 0.02),  // 2% gap on all sides
              child: _buildFollowStatsRow(),
            ),

            const SizedBox(height: 16),

            // Profile Information (compact card)
            Padding(
              padding: EdgeInsets.all(screenWidth * 0.02),  // 2% gap on all sides
              child: _buildDetailsCard(),
            ),

            const SizedBox(height: 24),

            // Action Buttons
            Padding(
              padding: EdgeInsets.all(screenWidth * 0.02),  // 2% gap on all sides
              child: Column(
                children: [
                  _buildActionTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'My Expenses',
                    subtitle: 'View your spending summary',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const UserExpensesScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildActionTile(
                    icon: Icons.logout,
                    title: 'Logout',
                    subtitle: 'Sign out of your account',
                    onTap: _showLogoutDialog,
                    isDestructive: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Future<void> _loadFollowCounts() async {
    try {
      if (_currentUser == null) return;
      final followers = await _firestoreService.getFollowersCount(
        _currentUser!.uid,
      );
      final following = await _firestoreService.getFollowingCount(
        _currentUser!.uid,
      );
      if (mounted) {
        setState(() {
          _followersCount = followers;
          _followingCount = following;
        });
      }
    } catch (_) {
      // ignore errors for counts; keep as zero
    }
  }

  Widget _buildFollowStatsRow() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    Widget stat(String label, int value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value.toString(),
                style: textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        stat('Followers', _followersCount),
        const SizedBox(width: 12),
        stat('Following', _followingCount),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  /// Modern header card showing avatar, name and bio
  Widget _buildHeaderCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileImageWidget(
            imageUrl:
                _currentUser!.profileImageUrl ??
                _profileImageNotifier.currentImageId,
            radius: 36,
            placeholder: Icon(
              Icons.person,
              size: 36,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentUser!.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.headlineSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _currentUser!.displayBio,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact details card with dense rows and dividers
  Widget _buildDetailsCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    List<Widget> rows = [];

    void addRow({
      required IconData icon,
      required String title,
      required String value,
      bool addDivider = true,
    }) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Text(
              '$title:',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
      if (addDivider) {
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: colorScheme.outlineVariant),
          ),
        );
      }
    }

    addRow(
      icon: Icons.email_outlined,
      title: 'Email',
      value: _currentUser!.email,
    );

    if (_currentUser!.phone != null && _currentUser!.phone!.isNotEmpty) {
      addRow(
        icon: Icons.phone_outlined,
        title: 'Phone',
        value: _currentUser!.phone!,
      );
    }

    if (_currentUser!.occupation != null && _currentUser!.occupation!.isNotEmpty) {
      addRow(
        icon: Icons.work_outline,
        title: 'Occupation',
        value: _currentUser!.occupation!,
      );
    }

    if (_currentUser!.age != null) {
      // Skip full-width row; will include in compact row below
    }

    if (_currentUser!.createdAt != null) {
      // Skip full-width row; will include in compact row below
    }

    // Add Age and Member Since as standard rows (no extra containers)
    if (_currentUser!.age != null) {
      addRow(
        icon: Icons.cake_outlined,
        title: 'Age',
        value: '${_currentUser!.age}',
      );
    }

    if (_currentUser!.createdAt != null) {
      addRow(
        icon: Icons.calendar_today_outlined,
        title: 'Member Since',
        value: _formatDate(_currentUser!.createdAt!),
        addDivider: false,
      );
    } else {
      // Remove trailing divider if last added had one
      if (rows.isNotEmpty && rows.last is Padding) {
        rows.removeLast();
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final Color fg = isDestructive
        ? colorScheme.error
        : colorScheme.onSurface;
    final Color iconBg = isDestructive
        ? colorScheme.error.withValues(alpha: 0.12)
        : colorScheme.primary.withValues(alpha: 0.12);
    final Color iconColor = isDestructive
        ? colorScheme.error
        : colorScheme.primary;

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final textTheme = theme.textTheme;

        return AlertDialog(
          title: Text(
            'Logout',
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to logout?',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
            TextButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final scaffoldMessenger = ScaffoldMessenger.of(context);

                try {
                  await _authService.signOut();
                  if (mounted) {
                    // Navigate back to login screen and clear all previous routes
                    navigator.pushNamedAndRemoveUntil('/', (route) => false);
                  }
                } catch (e) {
                  if (mounted) {
                    navigator.pop();
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text('Error logging out: $e'),
                        backgroundColor: colorScheme.error,
                      ),
                    );
                  }
                }
              },
              child: Text('Logout', style: TextStyle(color: colorScheme.error)),
            ),
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:roomie/data/models/notification_model.dart';
import 'package:roomie/presentation/screens/chat/chat_screen.dart';
import 'package:roomie/presentation/screens/chat/messages_page.dart';
import 'package:roomie/presentation/screens/groups/available_group_detail_s.dart';
import 'package:roomie/presentation/screens/groups/create_group_s.dart';
import 'package:roomie/presentation/screens/groups/current_group_detail_s.dart';
import 'package:roomie/presentation/screens/groups/join_requests_s.dart';
import 'package:roomie/presentation/screens/notifications/notifications_s.dart';
import 'package:roomie/presentation/screens/profile/user_profile_s.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/groups_service.dart';
import 'package:roomie/data/datasources/notification_service.dart';
import 'package:roomie/presentation/widgets/roomie_loading_widget.dart';
import 'package:roomie/presentation/screens/search/search_s.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController(initialPage: 1);
  int _currentPageIndex = 1; // 0: Search, 1: Home, 2: Messages

  final GroupsService _groupsService = GroupsService();
  final NotificationService _notificationService = NotificationService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _availableGroups = [];
  Map<String, dynamic>? _currentUserGroup;
  bool _isLoadingGroups = true;
  bool _canUserCreateGroup = true;

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  String _currencySymbol(String currency) {
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

  String _formatAmount(double amount, String currency, {String? suffix}) {
    if (amount <= 0) return 'Not specified';
    final formatter = NumberFormat.compactCurrency(
      symbol: _currencySymbol(currency),
      decimalDigits: 0,
    );
    final formatted = formatter.format(amount);
    if (suffix != null && suffix.isNotEmpty) {
      return '$formatted $suffix';
    }
    return formatted;
  }

  Map<String, dynamic> _parseRentDetails(Map<String, dynamic> group) {
    final dynamic rentRaw = group['rent'];
    double rentAmount = _toDouble(group['rentAmount']);
    String rentCurrency = (group['rentCurrency'] ?? '').toString();
    double advanceAmount = _toDouble(group['advanceAmount']);

    if (rentAmount == 0 && rentRaw != null) {
      if (rentRaw is Map<String, dynamic>) {
        rentAmount = _toDouble(rentRaw['amount']);
      } else if (rentRaw is num || rentRaw is String) {
        rentAmount = _toDouble(rentRaw);
      }
    }

    if (rentCurrency.isEmpty && rentRaw is Map<String, dynamic>) {
      rentCurrency = (rentRaw['currency'] ?? 'INR').toString();
    }
    if (rentCurrency.isEmpty) {
      rentCurrency = 'INR';
    }

    if (advanceAmount == 0 && rentRaw is Map<String, dynamic>) {
      advanceAmount = _toDouble(rentRaw['advanceAmount']);
    }

    return {
      'rentAmount': rentAmount,
      'rentCurrency': rentCurrency,
      'advanceAmount': advanceAmount,
    };
  }

  Widget _buildMetaChip({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationButton() {
    final userId = _authService.currentUser?.uid;

    if (userId == null) {
      return _buildNotificationIconShell();
    }

    return StreamBuilder<List<NotificationModel>>(
      stream: _notificationService.getNotifications(userId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildNotificationIconShell();
        }

        final notifications = snapshot.data ?? const [];
        final unreadCount =
            notifications.where((notification) => !notification.isRead).length;

        return _buildNotificationIconShell(unreadCount: unreadCount);
      },
    );
  }

  Widget _buildNotificationIconShell({int unreadCount = 0}) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: _buildNotificationIcon()),
          if (unreadCount > 0)
            Positioned(
              right: 0,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minHeight: 18, minWidth: 18),
                child: Center(
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: TextStyle(
                      color: colorScheme.onError,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotificationIcon() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NotificationsScreen(),
            ),
          );
        },
        icon: Icon(
          Icons.notifications_none,
          color: colorScheme.onSurface,
          size: 24,
        ),
        padding: EdgeInsets.zero,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUserGroupData();
  }

  Future<void> _loadUserGroupData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingGroups = true;
    });

    try {
      print('=== Loading user group data ===');
      final currentGroup = await _groupsService.getCurrentUserGroup();
      final canCreate = await _groupsService.canUserCreateGroup();
      final availableGroups = await _groupsService.getAvailableGroups();

      print('Current group: ${currentGroup?['name'] ?? 'None'}');
      print('Can create group: $canCreate');
      print('Available groups: ${availableGroups.length}');

      if (mounted) {
        setState(() {
          _currentUserGroup = currentGroup;
          _canUserCreateGroup = canCreate;
          _availableGroups = availableGroups;
          _isLoadingGroups = false;
        });
        print('UI updated with new data');
      }
    } catch (e) {
      print('Error loading user group data: $e');
      if (mounted) {
        setState(() {
          _isLoadingGroups = false;
        });
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error loading group data: $e',
              style: TextStyle(color: colorScheme.onError),
            ),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _leaveGroup() async {
    if (_currentUserGroup == null) return;

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Leave Group'),
              content: Text(
                'Are you sure you want to leave ${_currentUserGroup!['name']}?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('Leave'),
                ),
              ],
            ),
      );

      if (confirmed == true) {
        await _groupsService.leaveGroup(_currentUserGroup!['id']);
        // Pop the details screen
        if (mounted) Navigator.of(context).pop();
        await _loadUserGroupData(); // Refresh home screen data

        if (mounted) {
          final colorScheme = Theme.of(context).colorScheme;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Successfully left the group',
                style: TextStyle(color: colorScheme.onPrimary),
              ),
              backgroundColor: colorScheme.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error leaving group: $e',
              style: TextStyle(color: colorScheme.onError),
            ),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }

  void _navigateToGroupDetails() {
    if (_currentUserGroup == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => CurrentGroupDetailScreen(
              group: _currentUserGroup!,
              onLeaveGroup: _leaveGroup,
            ),
      ),
    ).then((_) => _loadUserGroupData());
  }

  void navigateToPage(int pageIndex) {
    _pageController.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPageIndex = index;
              });
            },
            children: [
              _buildSearchPage(),
              _buildHomeContent(),
              _buildMessagesPage(),
            ],
          ),
          // Page indicators
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildPageIndicator(0, 'Search'),
                const SizedBox(width: 12),
                _buildPageIndicator(1, 'Home'),
                const SizedBox(width: 12),
                _buildPageIndicator(2, 'Messages'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(int index, String label) {
    final isActive = _currentPageIndex == index;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => navigateToPage(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color:
              isActive
                  ? colorScheme.primary
                  : colorScheme.surface.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(16),
          border:
              isActive ? null : Border.all(color: colorScheme.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                isActive ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          // Custom App Bar
          Container(
            color: colorScheme.surface,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.04,  // 4% of screen width
                  vertical: screenHeight * 0.01,   // 1% of screen height
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Home',
                      style:
                          textTheme.headlineSmall?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ) ??
                          TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Row(
                      children: [
                        // Notifications button with badge
                        _buildNotificationButton(),
                        const SizedBox(width: 6),
                        // Profile button
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => const UserProfileScreen(),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.person_outline,
                              color: colorScheme.onSurface,
                              size: 24,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Add button - Only show if user can create (no current group)
                        if (_canUserCreateGroup)
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withValues(alpha: 0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: IconButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => const CreateGroupScreen(),
                                  ),
                                ).then((_) => _loadUserGroupData());
                              },
                              icon: Icon(
                                Icons.add,
                                color: colorScheme.onSurface,
                                size: 24,
                              ),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadUserGroupData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isLoadingGroups)
                      const Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Center(
                          child: RoomieLoadingWidget(
                            size: 80,
                            text: 'Loading groups...',
                            showText: true,
                          ),
                        ),
                      )
                    else ...[
                      // Current Room Section (show if user is in a group)
                      if (_currentUserGroup != null) ...[
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            screenWidth * 0.04,   // left: 4%
                            screenHeight * 0.005, // top: 0.5% (very small)
                            screenWidth * 0.04,   // right: 4%
                            screenHeight * 0.005, // bottom: 0.5%
                          ),
                          child: Text(
                            'Current Room',
                            style:
                                textTheme.titleLarge?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                ) ??
                                TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        _buildCozyCornerCard(screenWidth, screenHeight),
                        // Available Rooms section below current room
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            screenWidth * 0.04,    // left: 4%
                            screenHeight * 0.015,  // top: 1.5% (reduced from 3%)
                            screenWidth * 0.04,    // right: 4%
                            screenHeight * 0.01,   // bottom: 1%
                          ),
                          child: Text(
                            'Available Rooms',
                            style:
                                textTheme.titleLarge?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                ) ??
                                TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        _buildAvailableGroupsList(screenWidth, screenHeight),
                      ],
                      // Available Groups Section (only show if user has no group)
                      if (_currentUserGroup == null) ...[
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            screenWidth * 0.04,    // left: 4%
                            screenHeight * 0.005,  // top: 0.5% (very small)
                            screenWidth * 0.04,    // right: 4%
                            screenHeight * 0.01,   // bottom: 1%
                          ),
                          child: Text(
                            'Available Groups',
                            style:
                                textTheme.titleLarge?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                ) ??
                                TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        _buildAvailableGroupsList(screenWidth, screenHeight),
                      ],
                    ],
                    SizedBox(
                      height: screenHeight * 0.12,  // 12% of screen height (dynamic bottom padding)
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCozyCornerCard(double screenWidth, double screenHeight) {
    final pricing = _parseRentDetails(_currentUserGroup!);
    final double rentAmount = pricing['rentAmount'] as double;
    final String rentCurrency = pricing['rentCurrency'] as String;
    final double advanceAmount = pricing['advanceAmount'] as double;
    final String roomType =
        (_currentUserGroup!['roomType'] ?? 'Shared').toString();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.04,  // 4% horizontal gap (same as before)
        vertical: screenHeight * 0.01,   // 1% vertical gap
      ),
      child: GestureDetector(
        onTap: _navigateToGroupDetails,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: colorScheme.surface.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Group Image
                Container(
                  height: 200,
                  width: double.infinity,
                  color: colorScheme.surfaceContainerHighest,
                  child: Image.network(
                    _currentUserGroup!['imageUrl'] ??
                        'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=800',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Icon(
                          Icons.image,
                          color: colorScheme.onSurfaceVariant,
                          size: 50,
                        ),
                      );
                    },
                  ),
                ),
                // Group Details
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentUserGroup!['name'] ?? 'My Group',
                        style:
                            textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ) ??
                            TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentUserGroup!['description'] ??
                            'Your current group where you can connect with roommates.',
                        style:
                            textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ) ??
                            TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (rentAmount > 0)
                            _buildMetaChip(
                              icon: Icons.attach_money,
                              color: colorScheme.primary,
                              label: _formatAmount(
                                rentAmount,
                                rentCurrency,
                                suffix: 'per month',
                              ),
                            ),
                          if (advanceAmount > 0)
                            _buildMetaChip(
                              icon: Icons.account_balance_wallet_outlined,
                              color: colorScheme.secondary,
                              label: _formatAmount(
                                advanceAmount,
                                rentCurrency,
                                suffix: 'advance',
                              ),
                            ),
                          _buildMetaChip(
                            icon: Icons.home_outlined,
                            color: colorScheme.secondary,
                            label: roomType,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_currentUserGroup!['memberCount'] ?? 1} members',
                            style:
                                textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ) ??
                                TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                          // Chat Button
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => ChatScreen(
                                        chatData: _currentUserGroup!,
                                        chatType: 'group',
                                      ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Chat',
                              style:
                                  textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onPrimary,
                                  ) ??
                                  TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onPrimary,
                                  ),
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildAvailableGroupsList(double screenWidth, double screenHeight) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    if (_availableGroups.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.04,  // 4% horizontal gap
          vertical: screenHeight * 0.01,   // 1% vertical gap
        ),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(screenWidth * 0.06),  // 6% internal padding
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(
                Icons.group_add_outlined,
                color: colorScheme.onSurfaceVariant,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'No groups available',
                style:
                    textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ) ??
                    TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _canUserCreateGroup
                    ? 'Create your first group to get started'
                    : 'You are already in a group.',
                style:
                    textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ) ??
                    TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.04,  // 4% horizontal gap
        vertical: screenHeight * 0.01,   // 1% vertical gap
      ),
      child: Column(
        children:
            _availableGroups.map((group) {
              final pricing = _parseRentDetails(group);
              final double rentAmount = pricing['rentAmount'] as double;
              final String rentCurrency = pricing['rentCurrency'] as String;
              final double advanceAmount = pricing['advanceAmount'] as double;
              final String roomType =
                  (group['roomType'] ?? 'Shared').toString();

              return Container(
                margin: EdgeInsets.only(bottom: screenHeight * 0.02),  // 2% bottom margin
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: colorScheme.surface.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) =>
                                AvailableGroupDetailScreen(group: group),
                      ),
                    ).then(
                      (_) => _loadUserGroupData(),
                    ); // Refresh data when returning
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group['name'] ?? 'Unknown Group',
                                style:
                                    textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ) ??
                                    TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${group['location'] ?? 'Location'}, ${group['memberCount'] ?? 0} members',
                                style:
                                    textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ) ??
                                    TextStyle(
                                      fontSize: 14,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              if (group['description'] != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  group['description'],
                                  style:
                                      textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ) ??
                                      TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (rentAmount > 0)
                                    _buildMetaChip(
                                      icon: Icons.attach_money,
                                      color: colorScheme.primary,
                                      label: _formatAmount(
                                        rentAmount,
                                        rentCurrency,
                                        suffix: 'per month',
                                      ),
                                    ),
                                  if (advanceAmount > 0)
                                    _buildMetaChip(
                                      icon:
                                          Icons.account_balance_wallet_outlined,
                                      color: colorScheme.secondary,
                                      label: _formatAmount(
                                        advanceAmount,
                                        rentCurrency,
                                        suffix: 'advance',
                                      ),
                                    ),
                                  if (roomType.isNotEmpty)
                                    _buildMetaChip(
                                      icon: Icons.home_outlined,
                                      color: colorScheme.secondary,
                                      label: roomType,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: colorScheme.surfaceContainerHigh,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child:
                                group['imageUrl'] != null
                                    ? Image.network(
                                      group['imageUrl'],
                                      fit: BoxFit.cover,
                                      errorBuilder: (
                                        context,
                                        error,
                                        stackTrace,
                                      ) {
                                        return Icon(
                                          Icons.group,
                                          color: colorScheme.onSurfaceVariant,
                                          size: 30,
                                        );
                                      },
                                    )
                                    : Icon(
                                      Icons.group,
                                      color: colorScheme.onSurfaceVariant,
                                      size: 30,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildSearchPage() {
    return const SearchScreen();
  }

  Widget _buildMessagesPage() {
    return const MessagesPage();
  }
}

// Group Details Screen
class GroupDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> group;
  final bool isCurrentUserGroup;
  final VoidCallback? onLeaveGroup;

  const GroupDetailsScreen({
    super.key,
    required this.group,
    required this.isCurrentUserGroup,
    this.onLeaveGroup,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
        ),
        title: Text(
          group['name'] ?? 'Group Details',
          style:
              textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ) ??
              TextStyle(
                color: colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group Image
            Container(
              height: 250,
              width: double.infinity,
              color: colorScheme.surfaceContainerHighest,
              child: Image.network(
                group['imageUrl'] ??
                    'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=800',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Icon(
                      Icons.image,
                      color: colorScheme.onSurfaceVariant,
                      size: 50,
                    ),
                  );
                },
              ),
            ),

            // Group Details
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group['name'] ?? 'Group Name',
                    style:
                        textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ) ??
                        TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        color: colorScheme.onSurfaceVariant,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        group['location'] ?? 'Location',
                        style:
                            textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ) ??
                            TextStyle(
                              fontSize: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.people_outline,
                        color: colorScheme.onSurfaceVariant,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${group['memberCount'] ?? 0} members',
                        style:
                            textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ) ??
                            TextStyle(
                              fontSize: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Description',
                    style:
                        textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ) ??
                        TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    group['description'] ?? 'No description available.',
                    style:
                        textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ) ??
                        TextStyle(
                          fontSize: 16,
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  if (isCurrentUserGroup) ...[
                    // Manage Join Requests Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => JoinRequestsScreen(group: group),
                            ),
                          );
                        },
                        icon: const Icon(Icons.group_add, size: 18),
                        label: Text(
                          'Manage Join Requests',
                          style:
                              textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onPrimary,
                              ) ??
                              TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onPrimary,
                              ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Leave Group Button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: onLeaveGroup,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.error,
                          side: BorderSide(color: colorScheme.error),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Leave Group',
                          style:
                              textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.error,
                              ) ??
                              TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.error,
                              ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

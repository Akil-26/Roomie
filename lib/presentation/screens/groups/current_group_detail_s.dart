// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:roomie/presentation/screens/groups/join_requests_s.dart';
import 'package:roomie/presentation/screens/profile/other_user_profile_s.dart';
import 'package:roomie/data/datasources/firestore_service.dart';

class CurrentGroupDetailScreen extends StatefulWidget {
  final Map<String, dynamic> group;
  final VoidCallback? onLeaveGroup;

  const CurrentGroupDetailScreen({
    super.key,
    required this.group,
    this.onLeaveGroup,
  });

  @override
  State<CurrentGroupDetailScreen> createState() =>
      _CurrentGroupDetailScreenState();
}

class _CurrentGroupDetailScreenState extends State<CurrentGroupDetailScreen> {
  late Future<List<Map<String, dynamic>>> _membersFuture;
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final FirestoreService _firestoreService = FirestoreService();
  final Map<String, bool> _followingStatus = {};

  @override
  void initState() {
    super.initState();
    _membersFuture = _fetchGroupMembers();
    _membersFuture.then((members) => _checkFollowingStatus(members));
  }

  void _refreshFollowingStatus() {
    _membersFuture.then((members) => _checkFollowingStatus(members));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchGroupMembers() async {
    final memberIds = List<String>.from(widget.group['members'] ?? []);
    debugPrint('Group members IDs: $memberIds');
    if (memberIds.isEmpty) {
      return [];
    }

    final List<Map<String, dynamic>> membersList = [];

    // Fetch each member individually to ensure we get all data
    for (final memberId in memberIds) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(memberId)
            .get();

        final Map<String, dynamic> memberData = {'id': memberId};

        if (userDoc.exists && userDoc.data() != null) {
          // Merge Firestore data
          memberData.addAll(userDoc.data()!);
        }

        // No fallback to Firebase Auth displayName - only use Firestore data
        // If username is still empty after fetching from Firestore, it will be handled by _formatMemberDisplayName

        debugPrint('Fetched member $memberId: username=${memberData['username']}, name=${memberData['name']}, email=${memberData['email']}');
        membersList.add(memberData);
      } catch (e) {
        debugPrint('Error fetching member $memberId: $e');
        // Add member with just ID as fallback
        membersList.add({'id': memberId});
      }
    }

    debugPrint('Total members fetched: ${membersList.length}');
    return membersList;
  }

  Future<void> _checkFollowingStatus(List<Map<String, dynamic>> members) async {
    for (var member in members) {
      if (member['id'] != _currentUserId) {
        final isFollowing = await _firestoreService.isFollowing(
          _currentUserId,
          member['id'],
        );
        if (mounted) {
          setState(() {
            _followingStatus[member['id']] = isFollowing;
          });
        }
      }
    }
  }

  Future<void> _toggleFollow(String memberId) async {
    final isCurrentlyFollowing = _followingStatus[memberId] ?? false;
    if (mounted) {
      setState(() {
        _followingStatus[memberId] = !isCurrentlyFollowing;
      });
    }
    try {
      if (isCurrentlyFollowing) {
        await _firestoreService.unfollowUser(_currentUserId, memberId);
      } else {
        await _firestoreService.followUser(_currentUserId, memberId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _followingStatus[memberId] = isCurrentlyFollowing; // Revert on error
        });
      }
    }
  }

  String _formatMemberDisplayName(
    Map<String, dynamic> member,
    bool isCurrentUser,
  ) {
    String? _firstNonEmpty(List<dynamic> candidates) {
      for (final value in candidates) {
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
      return null;
    }

    final name = _firstNonEmpty([
      member['username'],
      member['name'],
      member['displayName'],
      member['userName'],
      member['fullName'],
    ]);

    final email = member['email'];
    final emailPrefix =
        email is String && email.trim().isNotEmpty
            ? email.trim().split('@').first
            : null;

    final phone = member['phone'];
    final phoneValue =
        phone is String && phone.trim().isNotEmpty ? phone.trim() : null;

    final fallback = name ?? emailPrefix ?? phoneValue ?? 'Member';

    if (isCurrentUser) {
      return '$fallback (You)';
    }
    return fallback;
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    return DateFormat.yMMMd().format(timestamp.toDate());
  }

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

  String _formatRent(double amount, String currency) {
    if (amount <= 0) return 'Not specified';
    final formatter = NumberFormat.compactCurrency(
      symbol: _currencySymbol(currency),
      decimalDigits: 0,
    );
    return '${formatter.format(amount)}/month';
  }

  String _formatAdvance(double amount, String currency) {
    if (amount <= 0) return 'No advance';
    final formatter = NumberFormat.compactCurrency(
      symbol: _currencySymbol(currency),
      decimalDigits: 0,
    );
    return '${formatter.format(amount)} deposit';
  }

  Future<void> _showLeaveGroupDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Leave Group'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Are you sure you want to leave this group?'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Leave'),
              onPressed: () {
                if (widget.onLeaveGroup != null) {
                  widget.onLeaveGroup!();
                }
                Navigator.of(context).pop(); // Close the dialog
                Navigator.of(
                  context,
                ).pop(); // Go back from the group detail screen
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    final List<String> images = List<String>.from(widget.group['images'] ?? []);
    final bool hasImages = images.isNotEmpty;
    final dynamic rentRaw = widget.group['rent'];
    double rentAmount = _toDouble(widget.group['rentAmount']);
    String rentCurrency = (widget.group['rentCurrency'] ?? '').toString();
    double advanceAmount = _toDouble(widget.group['advanceAmount']);

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

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: screenHeight * 0.35,  // 35% of screen height
            backgroundColor: colorScheme.surface,
            elevation: 0,
            pinned: true,
            stretch: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'group-image-${widget.group['id']}',
                child:
                    hasImages
                        ? _buildImageSlider(images)
                        : _buildPlaceholderImage(),
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.all(screenWidth * 0.05),  // 5% padding
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: Text(
                          widget.group['name'] ?? 'Unnamed Group',
                          style:
                              textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ) ??
                              TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                        ),
                      ),
                      SizedBox(width: screenWidth * 0.04),  // 4% gap
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.03,
                          vertical: screenHeight * 0.007,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Active',
                          style:
                              textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ) ??
                              TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenHeight * 0.02),  // 2% gap
                  Text(
                    widget.group['description'] ?? 'No description available.',
                    style:
                        textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ) ??
                        TextStyle(
                          fontSize: 16,
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                  ),
                  SizedBox(height: screenHeight * 0.03),  // 3% gap
                  Divider(height: 1, color: colorScheme.outlineVariant),
                  SizedBox(height: screenHeight * 0.03),  // 3% gap
                  _buildFullWidthInfoCard(
                    icon: Icons.location_on_outlined,
                    title: 'Location',
                    value: widget.group['location'] ?? 'Not specified',
                    color: colorScheme.primary,
                  ),
                  SizedBox(height: screenHeight * 0.02),  // 2% gap
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.attach_money,
                          title: 'Rent',
                          value: _formatRent(rentAmount, rentCurrency),
                          color: colorScheme.primary,
                        ),
                      ),
                      SizedBox(width: screenWidth * 0.04),  // 4% gap
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'Advance',
                          value: _formatAdvance(advanceAmount, rentCurrency),
                          color: colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenHeight * 0.02),  // 2% gap
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.group_outlined,
                          title: 'Roommates',
                          value: widget.group['capacity']?.toString() ?? 'N/A',
                          color: colorScheme.tertiary,
                        ),
                      ),
                      SizedBox(width: screenWidth * 0.04),  // 4% gap
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.home_outlined,
                          title: 'Room Type',
                          value: widget.group['roomType'] ?? 'N/A',
                          color: colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenHeight * 0.02),  // 2% gap
                  _buildInfoCard(
                    icon: Icons.calendar_today_outlined,
                    title: 'Created On',
                    value: _formatTimestamp(
                      widget.group['createdAt'] as Timestamp?,
                    ),
                    color: colorScheme.tertiary,
                  ),
                  SizedBox(height: screenHeight * 0.03),  // 3% gap
                  if (widget.group['amenities'] != null &&
                      (widget.group['amenities'] as List).isNotEmpty) ...[
                    Text(
                      'Facilities',
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
                    SizedBox(height: screenHeight * 0.015),  // 1.5% gap
                    _buildAmenitiesGrid(
                      List<String>.from(widget.group['amenities']),
                    ),
                    SizedBox(height: screenHeight * 0.03),  // 3% gap
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Members',
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => JoinRequestsScreen(
                                        group: widget.group,
                                      ),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.person_add_outlined,
                              size: screenWidth * 0.065,
                              color: colorScheme.primary,
                            ),
                            tooltip: 'Manage Requests',
                          ),
                          IconButton(
                            onPressed: _showLeaveGroupDialog,
                            icon: Icon(
                              Icons.logout_outlined,
                              size: screenWidth * 0.065,
                              color: colorScheme.error,
                            ),
                            tooltip: 'Leave Group',
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: screenHeight * 0.015),  // 1.5% gap
                  _buildMembersSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSlider(List<String> images) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: images.length,
          onPageChanged: (index) {
            setState(() {
              _currentImageIndex = index;
            });
          },
          itemBuilder: (context, index) {
            return Image.network(
              images[index],
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildPlaceholderImage();
              },
            );
          },
        ),
        if (images.length > 1)
          Positioned(
            bottom: screenHeight * 0.012,  // 1.2% from bottom
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (index) {
                return Container(
                  width: screenWidth * 0.02,  // 2% width
                  height: screenWidth * 0.02,  // 2% height (keep square)
                  margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.01),  // 1% margin
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        _currentImageIndex == index
                            ? colorScheme.surface
                            : colorScheme.surface.withValues(alpha: 0.5),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceholderImage() {
    final screenWidth = MediaQuery.of(context).size.width;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.group, color: colorScheme.onSurfaceVariant, size: screenWidth * 0.15),  // 15% icon
      ),
    );
  }

  Widget _buildAmenitiesGrid(List<String> amenities) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Wrap(
      spacing: screenWidth * 0.02,  // 2% spacing
      runSpacing: screenHeight * 0.01,  // 1% run spacing
      children:
          amenities.map((amenity) {
            return Container(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.03, vertical: screenHeight * 0.007),  // Dynamic padding
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Text(
                amenity,
                style:
                    textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ) ??
                    TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildMembersSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _membersFuture,
      builder: (context, snapshot) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final textTheme = theme.textTheme;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: colorScheme.primary),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              'No members found.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        final members = snapshot.data!;
        return Column(
          children:
              members.map((member) {
                final isCreator = member['uid'] == widget.group['createdBy'];
                final isCurrentUser = member['id'] == _currentUserId;
                final isFollowing = _followingStatus[member['id']] ?? false;

                debugPrint(
                  'Building member item: ${member['name']}, isCurrentUser: $isCurrentUser, isCreator: $isCreator',
                );

                return Container(
                  margin: EdgeInsets.only(bottom: screenHeight * 0.01),  // 1% margin
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListTile(
                    onTap: () async {
                      if (!isCurrentUser) {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => OtherUserProfileScreen(
                                  userId: member['id'],
                                ),
                          ),
                        );
                        // Refresh following status when returning
                        _refreshFollowingStatus();
                      }
                    },
                    contentPadding: EdgeInsets.fromLTRB(
                      screenWidth * 0.04,  // 4% left
                      screenHeight * 0.005,  // 0.5% top
                      screenWidth * 0.04,  // 4% right
                      screenHeight * 0.005,  // 0.5% bottom
                    ),
                    leading: CircleAvatar(
                      radius: screenWidth * 0.05,  // 5% radius
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      backgroundImage:
                          member['profileImageUrl'] != null
                              ? NetworkImage(member['profileImageUrl'])
                              : null,
                      child:
                          member['profileImageUrl'] == null
                              ? Icon(
                                Icons.person,
                                color: colorScheme.onSurfaceVariant,
                              )
                              : null,
                    ),
                    title: Text(
                      _formatMemberDisplayName(member, isCurrentUser),
                      style:
                          textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ) ??
                          const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing:
                        isCreator
                            ? Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: screenWidth * 0.02,  // 2% horizontal
                                vertical: screenHeight * 0.005,  // 0.5% vertical
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Admin',
                                style:
                                    textTheme.labelSmall?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ) ??
                                    TextStyle(
                                      color: colorScheme.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            )
                            : (isCurrentUser
                                ? null // No trailing widget for current user (already has "You" in title)
                                : (!isFollowing
                                    ? ElevatedButton(
                                      onPressed: () => _toggleFollow(member['id']),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: colorScheme.primary,
                                        foregroundColor: colorScheme.onPrimary,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: screenWidth * 0.04,  // 4% horizontal
                                          vertical: screenHeight * 0.002,  // 0.2% vertical
                                        ),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        minimumSize: Size(0, screenHeight * 0.037),  // 3.7% height
                                      ),
                                      child: const Text('Follow'),
                                    )
                                    : const SizedBox.shrink())),
                  ),
                );
              }).toList(),
        );
      },
    );
  }

  Widget _buildFullWidthInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.04),  // 4% padding
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: screenWidth * 0.055),  // 5.5% icon
          SizedBox(width: screenWidth * 0.03),  // 3% gap
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ) ??
                      TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                SizedBox(height: screenHeight * 0.005),  // 0.5% gap
                Text(
                  value,
                  style:
                      textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ) ??
                      TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.04),  // 4% padding
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: screenWidth * 0.055),  // 5.5% icon
              SizedBox(width: screenWidth * 0.02),  // 2% gap
              Text(
                title,
                style:
                    textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ) ??
                    TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
          SizedBox(height: screenHeight * 0.01),  // 1% gap
          Text(
            value,
            style:
                textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ) ??
                TextStyle(
                  fontSize: 16,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

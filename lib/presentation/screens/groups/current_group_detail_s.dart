// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:roomie/presentation/screens/groups/join_requests_s.dart';
import 'package:roomie/presentation/screens/groups/owner_join_requests_s.dart';
import 'package:roomie/presentation/screens/groups/ownership_requests_s.dart';
import 'package:roomie/presentation/screens/groups/room_payments_s.dart';
import 'package:roomie/presentation/screens/groups/owner_payment_dashboard_s.dart';
import 'package:roomie/presentation/screens/profile/other_user_profile_s.dart';
import 'package:roomie/data/datasources/firestore_service.dart';
import 'package:roomie/data/datasources/room_payment_service.dart';
import 'package:roomie/data/datasources/groups_service.dart';

class CurrentGroupDetailScreen extends StatefulWidget {
  final Map<String, dynamic> group;
  final Future<void> Function()? onLeaveGroup;

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
  final RoomPaymentService _paymentService = RoomPaymentService();
  final GroupsService _groupsService = GroupsService();
  final Map<String, bool> _followingStatus = {};
  
  // Step-3: Room owner and payment eligibility state
  bool _isRoomOwner = false;
  bool _canMakePayment = false;
  bool _isRoomCreator = false;
  int _pendingOwnershipRequests = 0;
  // Step-4: Join requests for owner-created rooms
  int _pendingJoinRequests = 0;

  @override
  void initState() {
    super.initState();
    _membersFuture = _fetchGroupMembers();
    _membersFuture.then((members) => _checkFollowingStatus(members));
    _loadOwnershipAndPaymentState();
  }

  /// Load ownership and payment eligibility state for Step-3
  Future<void> _loadOwnershipAndPaymentState() async {
    try {
      final roomId = widget.group['id'];
      final creatorId = widget.group['createdBy'];
      
      // Check if current user is room creator (admin)
      final isCreator = creatorId == _currentUserId;
      
      // Check if current user is room owner
      final isOwner = await _paymentService.isRoomOwner(roomId);
      
      // Check if payments can be made (room has owner)
      final canPay = await _paymentService.canMakePayment(roomId);
      
      // Get pending ownership requests count (for creator)
      int pendingRequests = 0;
      if (isCreator) {
        final requests = await _groupsService.getPendingOwnershipRequests(roomId);
        pendingRequests = requests.length;
      }
      
      // Step-4: Get pending join requests count (for owner)
      int pendingJoins = 0;
      if (isOwner) {
        final joinRequests = await _groupsService.getPendingJoinRequests(roomId);
        pendingJoins = joinRequests.length;
      }
      
      if (mounted) {
        setState(() {
          _isRoomCreator = isCreator;
          _isRoomOwner = isOwner;
          _canMakePayment = canPay;
          _pendingOwnershipRequests = pendingRequests;
          _pendingJoinRequests = pendingJoins;
        });
      }
    } catch (e) {
      debugPrint('Error loading ownership state: $e');
    }
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
      builder: (BuildContext dialogContext) {
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
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('Leave'),
              onPressed: () async {
                // Close the dialog first
                Navigator.of(dialogContext).pop();
                
                // Execute the leave action
                if (widget.onLeaveGroup != null) {
                  await widget.onLeaveGroup!();
                }
                
                // Navigate back to home after leaving
                if (mounted) {
                  Navigator.of(context).pop();
                }
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
                  
                  // === STEP-3: Quick Actions Section ===
                  _buildQuickActionsSection(screenWidth, screenHeight, colorScheme, textTheme),
                  SizedBox(height: screenHeight * 0.03),  // 3% gap
                  
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

  /// STEP-3: Build quick actions section for payments and ownership
  Widget _buildQuickActionsSection(
    double screenWidth,
    double screenHeight,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final roomId = widget.group['id'] as String;
    final roomName = widget.group['name'] as String? ?? 'Room';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ) ?? TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: screenHeight * 0.015),
        
        Row(
          children: [
            // Payment button (for all members)
            Expanded(
              child: _buildQuickActionCard(
                icon: Icons.payment,
                title: _isRoomOwner ? 'Payment Dashboard' : 'Pay Rent',
                subtitle: _isRoomOwner 
                    ? 'View all payments' 
                    : (_canMakePayment ? 'Pay to owner' : 'No owner yet'),
                color: Colors.green,
                isEnabled: _canMakePayment || _isRoomOwner,
                onTap: () {
                  if (_isRoomOwner) {
                    // Owner sees payment dashboard
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OwnerPaymentDashboardScreen(
                          roomId: roomId,
                          roomName: roomName,
                        ),
                      ),
                    );
                  } else if (_canMakePayment) {
                    // Roommate sees payment screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RoomPaymentsScreen(
                          roomId: roomId,
                          roomName: roomName,
                        ),
                      ),
                    );
                  }
                },
                screenWidth: screenWidth,
                screenHeight: screenHeight,
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
            SizedBox(width: screenWidth * 0.03),
            
            // Ownership requests button (for room creator only)
            if (_isRoomCreator)
              Expanded(
                child: Stack(
                  children: [
                    _buildQuickActionCard(
                      icon: Icons.verified_user,
                      title: 'Ownership',
                      subtitle: 'Manage requests',
                      color: Colors.blue,
                      isEnabled: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => OwnershipRequestsScreen(
                              roomId: roomId,
                              roomName: roomName,
                            ),
                          ),
                        ).then((_) => _loadOwnershipAndPaymentState());
                      },
                      screenWidth: screenWidth,
                      screenHeight: screenHeight,
                      colorScheme: colorScheme,
                      textTheme: textTheme,
                    ),
                    // Badge for pending requests
                    if (_pendingOwnershipRequests > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$_pendingOwnershipRequests',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        
        // Step-4: Join Requests row for room owner
        if (_isRoomOwner) ...[
          SizedBox(height: screenHeight * 0.015),
          Stack(
            children: [
              _buildQuickActionCard(
                icon: Icons.person_add,
                title: 'Join Requests',
                subtitle: _pendingJoinRequests > 0 
                    ? '$_pendingJoinRequests pending' 
                    : 'Manage requests',
                color: Colors.purple,
                isEnabled: true,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OwnerJoinRequestsScreen(
                        roomId: roomId,
                        roomName: roomName,
                      ),
                    ),
                  ).then((_) => _loadOwnershipAndPaymentState());
                },
                screenWidth: screenWidth,
                screenHeight: screenHeight,
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
              // Badge for pending join requests
              if (_pendingJoinRequests > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$_pendingJoinRequests',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isEnabled,
    required VoidCallback onTap,
    required double screenWidth,
    required double screenHeight,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return InkWell(
      onTap: isEnabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(screenWidth * 0.04),
        decoration: BoxDecoration(
          color: isEnabled 
              ? colorScheme.surface 
              : colorScheme.surfaceContainerHighest.withAlpha(100),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isEnabled ? color.withAlpha(100) : colorScheme.outlineVariant,
          ),
          boxShadow: isEnabled ? [
            BoxShadow(
              color: color.withAlpha(20),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isEnabled ? color.withAlpha(30) : Colors.grey.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isEnabled ? color : Colors.grey,
                size: screenWidth * 0.06,
              ),
            ),
            SizedBox(height: screenHeight * 0.01),
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isEnabled ? colorScheme.onSurface : Colors.grey,
              ),
            ),
            SizedBox(height: screenHeight * 0.003),
            Text(
              subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: isEnabled ? colorScheme.onSurfaceVariant : Colors.grey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
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

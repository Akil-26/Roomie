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

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final ProfileImageNotifier _profileImageNotifier = ProfileImageNotifier();
  UserModel? _currentUser;
  bool _isLoading = true;
  int _followersCount = 0;
  int _followingCount = 0;
  
  // Animation controller
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    // Initialize animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    
    _loadUserData();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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
          
          // 🔒 SECURITY: Session protection - verify UID matches
          // This prevents accidental account switching
          final currentAuthUid = _authService.currentUser?.uid;
          if (currentAuthUid != null && currentAuthUid != user.uid) {
            print('⚠️ Security: UID mismatch detected! Force logging out...');
            await _authService.signOut();
            if (mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
            }
            return;
          }
          
          setState(() {
            _currentUser = UserModel.fromMap(userData, user.uid);
            _isLoading = false;
          });
          
          // Start animation after data loads
          _animationController.forward();

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
          
          // Start animation
          _animationController.forward();
          
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
      final colorScheme = Theme.of(context).colorScheme;
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: _buildSkeletonLoading(colorScheme, screenWidth, screenHeight),
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
      body: CustomScrollView(
        slivers: [
          // Modern SliverAppBar with gradient hero
          SliverAppBar(
            expandedHeight: screenHeight * 0.38,
            floating: false,
            pinned: true,
            backgroundColor: colorScheme.surface,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surface.withOpacity(0.8),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withOpacity(0.8),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.edit_rounded, color: colorScheme.primary),
                  onPressed: () => _navigateToEditProfile(),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeroSection(colorScheme, textTheme, screenHeight),
            ),
          ),
          
          // Content
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      
                      // Stats Cards Row
                      _buildStatsRow(colorScheme, textTheme),
                      
                      const SizedBox(height: 20),
                      
                      // About Section
                      _buildAboutSection(colorScheme, textTheme),
                      
                      const SizedBox(height: 16),
                      
                      // Quick Actions
                      _buildQuickActions(colorScheme, textTheme),
                      
                      SizedBox(height: screenHeight * 0.05),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToEditProfile() async {
    if (_currentUser != null) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditProfileScreen(currentUser: _currentUser!),
        ),
      );

      if (result is Map) {
        final newUrl = result['profileImageUrl'] as String?;
        if (newUrl != null && newUrl.isNotEmpty) {
          _profileImageNotifier.updateProfileImage(newUrl);
          setState(() {
            _currentUser = _currentUser!.copyWith(profileImageUrl: newUrl);
          });
        }
        _loadUserData();
      } else if (result == true) {
        _loadUserData();
      }
    }
  }

  // Hero section with gradient and profile info
  Widget _buildHeroSection(ColorScheme colorScheme, TextTheme textTheme, double screenHeight) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            colorScheme.primary.withOpacity(0.8),
            colorScheme.secondary.withOpacity(0.6),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          
          // Profile content
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  
                  // Profile Image with gradient ring
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          Colors.white.withOpacity(0.6),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ProfileImageWidget(
                      imageUrl: _currentUser!.profileImageUrl ??
                          _profileImageNotifier.currentImageId,
                      radius: 50,
                      placeholder: Icon(
                        Icons.person_rounded,
                        size: 50,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Username
                  Text(
                    _currentUser!.displayName,
                    style: textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 6),
                  
                  // Bio
                  if (_currentUser!.bio != null && _currentUser!.bio!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        _currentUser!.bio!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    
                  const SizedBox(height: 12),
                  
                  // Member badge
                  if (_currentUser!.createdAt != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Member since ${_formatDate(_currentUser!.createdAt!)}',
                            style: textTheme.bodySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Stats row with followers/following - compact inline design
  Widget _buildStatsRow(ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              value: _followersCount.toString(),
              label: 'Followers',
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
          ),
          Container(
            height: 32,
            width: 1,
            color: colorScheme.outlineVariant.withOpacity(0.4),
          ),
          Expanded(
            child: _buildStatItem(
              value: _followingCount.toString(),
              label: 'Following',
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String value,
    required String label,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // About section with user details - cleaner chip layout
  Widget _buildAboutSection(ColorScheme colorScheme, TextTheme textTheme) {
    final infoItems = <Widget>[];
    
    if (_currentUser!.email.isNotEmpty) {
      infoItems.add(_buildInfoChip(
        icon: Icons.mail_outline_rounded,
        label: 'Email',
        value: _currentUser!.email,
        colorScheme: colorScheme,
        textTheme: textTheme,
      ));
    }
    
    if (_currentUser!.phone != null && _currentUser!.phone!.isNotEmpty) {
      infoItems.add(_buildInfoChip(
        icon: Icons.phone_outlined,
        label: 'Phone',
        value: _currentUser!.phone!,
        colorScheme: colorScheme,
        textTheme: textTheme,
      ));
    }
    
    if (_currentUser!.occupation != null && _currentUser!.occupation!.isNotEmpty) {
      infoItems.add(_buildInfoChip(
        icon: Icons.work_outline_rounded,
        label: 'Occupation',
        value: _currentUser!.occupation!,
        colorScheme: colorScheme,
        textTheme: textTheme,
      ));
    }
    
    if (_currentUser!.age != null) {
      infoItems.add(_buildInfoChip(
        icon: Icons.cake_outlined,
        label: 'Age',
        value: '${_currentUser!.age}',
        colorScheme: colorScheme,
        textTheme: textTheme,
      ));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: colorScheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Details',
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: infoItems,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Quick actions section - compact buttons
  Widget _buildQuickActions(ColorScheme colorScheme, TextTheme textTheme) {
    return Row(
      children: [
        Expanded(
          child: _buildCompactAction(
            icon: Icons.receipt_long_rounded,
            label: 'Expenses',
            colorScheme: colorScheme,
            textTheme: textTheme,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UserExpensesScreen()),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildCompactAction(
            icon: Icons.logout_rounded,
            label: 'Logout',
            colorScheme: colorScheme,
            textTheme: textTheme,
            onTap: _showLogoutDialog,
            isDestructive: true,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactAction({
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? colorScheme.error : colorScheme.primary;
    
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withOpacity(0.2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
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

  // Skeleton loading for profile page
  Widget _buildSkeletonLoading(ColorScheme colorScheme, double screenWidth, double screenHeight) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Hero section skeleton - use intrinsic height instead of fixed
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary.withOpacity(0.3),
                  colorScheme.primary.withOpacity(0.2),
                  colorScheme.secondary.withOpacity(0.15),
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App bar skeleton
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildShimmerCircle(40, colorScheme),
                          _buildShimmerCircle(40, colorScheme),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Profile image skeleton
                    _buildShimmerCircle(96, colorScheme),
                    
                    const SizedBox(height: 12),
                    
                    // Name skeleton
                    _buildShimmerBox(120, 20, colorScheme),
                    
                    const SizedBox(height: 8),
                    
                    // Bio skeleton
                    _buildShimmerBox(160, 14, colorScheme),
                    
                    const SizedBox(height: 10),
                    
                    // Member badge skeleton
                    _buildShimmerBox(110, 24, colorScheme, radius: 12),
                  ],
                ),
              ),
            ),
          ),
          
          // Content skeleton
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const SizedBox(height: 16),
                
                // Stats row skeleton
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _buildShimmerBox(36, 24, colorScheme),
                            const SizedBox(height: 6),
                            _buildShimmerBox(56, 12, colorScheme),
                          ],
                        ),
                      ),
                      Container(
                        height: 28,
                        width: 1,
                        color: colorScheme.outlineVariant.withOpacity(0.3),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            _buildShimmerBox(36, 24, colorScheme),
                            const SizedBox(height: 6),
                            _buildShimmerBox(56, 12, colorScheme),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Details section skeleton
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          _buildShimmerBox(16, 16, colorScheme, radius: 4),
                          const SizedBox(width: 8),
                          _buildShimmerBox(50, 14, colorScheme),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Chips skeleton - use smaller fixed widths
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildShimmerBox(120, 36, colorScheme, radius: 8),
                          _buildShimmerBox(90, 36, colorScheme, radius: 8),
                          _buildShimmerBox(80, 36, colorScheme, radius: 8),
                          _buildShimmerBox(60, 36, colorScheme, radius: 8),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 14),
                
                // Action buttons skeleton
                Row(
                  children: [
                    Expanded(
                      child: _buildShimmerBox(double.infinity, 44, colorScheme, radius: 12),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildShimmerBox(double.infinity, 44, colorScheme, radius: 12),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerBox(double width, double height, ColorScheme colorScheme, {double radius = 6}) {
    return _ShimmerBox(
      width: width,
      height: height,
      radius: radius,
      colorScheme: colorScheme,
    );
  }

  Widget _buildShimmerCircle(double size, ColorScheme colorScheme) {
    return _ShimmerCircle(size: size, colorScheme: colorScheme);
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

// Shimmer box widget with repeating animation
class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final ColorScheme colorScheme;

  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.radius,
    required this.colorScheme,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.colorScheme.surfaceContainerHigh.withOpacity(_animation.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

// Shimmer circle widget with repeating animation
class _ShimmerCircle extends StatefulWidget {
  final double size;
  final ColorScheme colorScheme;

  const _ShimmerCircle({
    required this.size,
    required this.colorScheme,
  });

  @override
  State<_ShimmerCircle> createState() => _ShimmerCircleState();
}

class _ShimmerCircleState extends State<_ShimmerCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.2, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_animation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

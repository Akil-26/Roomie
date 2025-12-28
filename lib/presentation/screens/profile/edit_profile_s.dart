// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:roomie/data/datasources/firestore_service.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/models/user_model.dart';
import 'package:roomie/presentation/widgets/profile_image_widget.dart';
import 'package:roomie/presentation/screens/auth/otp_s.dart';
import 'dart:io';

class EditProfileScreen extends StatefulWidget {
  final UserModel currentUser;

  const EditProfileScreen({super.key, required this.currentUser});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final ImagePicker _imagePicker = ImagePicker();
  
  // Animation controller for smooth transitions
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Controllers for form fields
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _bioController;
  late TextEditingController _phoneController;
  late TextEditingController _occupationController;
  late TextEditingController _ageController;

  File? _selectedImage;
  XFile? _selectedXFile; // For web compatibility
  bool _isLoading = false;
  String? _currentProfileImageUrl;
  
  // Email state - only for first-time adding (phone login users)
  String? _addedEmail; // New email added by user (only if they had no email)
  bool _isAddingEmail = false;
  
  // Phone verification state
  bool _phoneVerified = false;
  String? _originalPhone; // Store original phone to detect changes
  bool _isCheckingPhone = false;

  @override
  void initState() {
    super.initState();
    // Initialize animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _animationController.forward();
    
    // Initialize controllers with current user data
    _usernameController = TextEditingController(
      text: widget.currentUser.username ?? '',
    );
    _emailController = TextEditingController(
      text: widget.currentUser.email,
    );
    _bioController = TextEditingController(text: widget.currentUser.bio ?? '');
    _phoneController = TextEditingController(
      text: widget.currentUser.phone ?? '',
    );
    _originalPhone = widget.currentUser.phone ?? ''; // Store original phone
    _phoneVerified = (widget.currentUser.phone ?? '').isNotEmpty; // Already verified if has phone
    _occupationController = TextEditingController(
      text: widget.currentUser.occupation ?? '',
    );
    _ageController = TextEditingController(
      text: widget.currentUser.age?.toString() ?? '',
    );
    _currentProfileImageUrl = widget.currentUser.profileImageUrl;
  }

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _occupationController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (image != null) {
        setState(() {
          _selectedXFile = image;
          // For mobile compatibility, also set File if not web
          if (!kIsWeb) {
            _selectedImage = File(image.path);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    // 🔒 Check if phone number changed and needs verification
    final currentPhone = _phoneController.text.trim();
    final originalPhone = _originalPhone ?? '';
    final phoneChanged = _normalizePhone(currentPhone) != _normalizePhone(originalPhone);
    
    if (phoneChanged && currentPhone.isNotEmpty && !_phoneVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('⚠️ Please verify your new phone number before saving'),
          backgroundColor: Theme.of(context).colorScheme.tertiary,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('User not found');

      // Parse age
      int? age;
      if (_ageController.text.isNotEmpty) {
        age = int.tryParse(_ageController.text);
        if (age == null) {
          throw Exception('Invalid age format');
        }
      }

      // 🔒 Check if phone is taken (double-check before save)
      // Only check if the phone has actually changed to a DIFFERENT number
      // Skip check if user is keeping their own original phone number
      if (currentPhone.isNotEmpty && phoneChanged) {
        final isTaken = await _firestoreService.isPhoneTaken(currentPhone, user.uid);
        if (isTaken) {
          throw Exception('This phone number is already registered with another account');
        }
      }

      // 🔒 Email handling:
      // - If user already has email: keep it (cannot change)
      // - If user added new email via Google: use the new one
      // - Once set, email cannot be changed
      final emailToSave = _addedEmail ?? widget.currentUser.email;

      // Show a specific message if trying to upload image
      if (_selectedXFile != null) {
        if (mounted) {
          final colorScheme = Theme.of(context).colorScheme;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Uploading profile image...'),
              backgroundColor: colorScheme.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      // Determine phone to save - only save verified phone
      final phoneToSave = _phoneVerified ? currentPhone : originalPhone;

      // First save the profile with image (if new image selected)
      await _firestoreService.saveUserProfile(
        userId: user.uid,
        username: _usernameController.text.trim(),
        bio: _bioController.text.trim(),
        email: emailToSave,
        phone: phoneToSave,
        profileImage: _selectedXFile ?? _selectedImage, // Pass XFile or File
        occupation:
            _occupationController.text.trim().isEmpty
                ? null
                : _occupationController.text.trim(),
        age: age,
      );

      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile updated successfully!'),
            backgroundColor: colorScheme.secondary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Fetch fresh doc to obtain latest profileImageUrl immediately
        final fresh =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
        final freshData = fresh.data();
        final freshUrl = freshData?['profileImageUrl'] as String?;
        if (mounted) {
          Navigator.of(context).pop({'profileImageUrl': freshUrl});
        }
      }
    } catch (e) {
      print('Error updating profile: $e'); // Add debugging
      if (mounted) {
        final errorScheme = Theme.of(context).colorScheme;
        String errorMessage = 'Error updating profile: $e';
        
        // 🔒 Show specific error for email conflict
        if (e.toString().contains('email already exists')) {
          errorMessage = '❌ This email already exists in Roomie. Please use a different email.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: errorScheme.error,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _reauthenticateUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    // Check if user signed in with Google
    final isGoogleUser = user.providerData.any(
      (info) => info.providerId == 'google.com',
    );

    if (isGoogleUser) {
      // Re-authenticate with Google using AuthService
      try {
        final authService = _authService;
        
        // Show loading dialog
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Sign in with Google again to get fresh credentials
        await authService.signInWithGoogle();
        
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
        }

        return true;
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Close loading dialog if still open
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Google re-authentication failed: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return false;
      }
    }

    // For email/password users, show password dialog
    final passwordController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        return AlertDialog(
          title: Text(
            'Confirm your password',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'For security, please enter your password to continue.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, passwordController.text),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) return false;

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: result,
      );
      await user.reauthenticateWithCredential(credential);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Invalid password. Please try again.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return false;
    }
  }

  // Add email for first-time users (phone login users who don't have email)
  // This only GETS the Google email, does NOT sign in or change user
  Future<void> _addEmailViaGoogle() async {
    final colorScheme = Theme.of(context).colorScheme;
    
    // 🔒 SECURITY: Don't allow if user already has an email
    if (widget.currentUser.email.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('❌ You already have an email. Email cannot be changed.'),
          backgroundColor: colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    setState(() => _isAddingEmail = true);
    
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text(
                'Select Google account...',
                style: TextStyle(color: colorScheme.onSurface),
              ),
            ],
          ),
        ),
      );

      // Use GoogleSignIn just to GET the email, not sign in to Firebase
      final GoogleSignIn googleSignIn = GoogleSignIn(scopes: ['email']);
      
      // Sign out first to ensure account picker shows
      try {
        await googleSignIn.signOut();
      } catch (_) {}
      
      // Show Google account picker
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
      }
      
      if (googleUser == null) {
        // User cancelled
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Google sign-in cancelled'),
              backgroundColor: colorScheme.onSurfaceVariant,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      
      final newEmail = googleUser.email;
      
      // 🔒 SECURITY: Check if this email already exists for ANY user in Firestore
      // Use the CURRENT user's ID (phone user), not Google's
      final currentUserId = widget.currentUser.uid;
      final isEmailTaken = await _firestoreService.isEmailTaken(newEmail, currentUserId);
      
      if (isEmailTaken) {
        // Email belongs to another user - show error and sign out from Google
        await googleSignIn.signOut();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('❌ This email is already registered with another Roomie account. Please use a different Google account.'),
              backgroundColor: colorScheme.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      
      // Sign out from GoogleSignIn (we just needed the email)
      await googleSignIn.signOut();
      
      // Email is available - save it
      setState(() {
        _addedEmail = newEmail;
        _emailController.text = newEmail;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Email added: $newEmail (Save to confirm)'),
            backgroundColor: colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // Try to close dialog if still open
        try { Navigator.pop(context); } catch (_) {}
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add email: $e'),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAddingEmail = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          // Modern SliverAppBar with gradient hero section
          SliverAppBar(
            expandedHeight: screenHeight * 0.32,
            pinned: true,
            stretch: true,
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surface.withOpacity(0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(Icons.close_rounded, color: colorScheme.onSurface),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        )
                      : Text(
                          'Save',
                          style: textTheme.titleSmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Gradient background
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [
                                colorScheme.primary.withOpacity(0.3),
                                colorScheme.secondary.withOpacity(0.2),
                                colorScheme.surface,
                              ]
                            : [
                                colorScheme.primary.withOpacity(0.15),
                                colorScheme.secondary.withOpacity(0.1),
                                colorScheme.surface,
                              ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                  // Decorative circles
                  Positioned(
                    top: -50,
                    right: -50,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.primary.withOpacity(0.1),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 80,
                    left: -30,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.secondary.withOpacity(0.1),
                      ),
                    ),
                  ),
                  // Profile image section
                  SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        // Profile Image with gradient ring
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Stack(
                              children: [
                                // Outer gradient ring
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        colorScheme.primary,
                                        colorScheme.secondary,
                                      ],
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: colorScheme.surface,
                                    ),
                                    child: ProfileImageWidget(
                                      imageUrl: _currentProfileImageUrl,
                                      localPreviewFile: !kIsWeb ? _selectedImage : null,
                                      radius: screenWidth * 0.15,
                                      placeholder: Icon(
                                        Icons.person_rounded,
                                        size: screenWidth * 0.15,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                // Camera button
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: colorScheme.surface,
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: colorScheme.primary.withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.camera_alt_rounded,
                                      color: colorScheme.onPrimary,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Status text with animation
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            _selectedXFile != null || _selectedImage != null
                                ? '✨ New photo selected'
                                : 'Tap to change photo',
                            key: ValueKey(_selectedXFile != null || _selectedImage != null),
                            style: textTheme.bodyMedium?.copyWith(
                              color: _selectedXFile != null || _selectedImage != null
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Form content
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Form(
                key: _formKey,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // Profile Section Card
                      _buildSectionCard(
                        title: 'Profile',
                        icon: Icons.person_outline_rounded,
                        colorScheme: colorScheme,
                        textTheme: textTheme,
                        children: [
                          _buildTextField(
                            controller: _usernameController,
                            label: 'Username',
                            hint: 'Enter your username',
                            icon: Icons.alternate_email_rounded,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Username is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _bioController,
                            label: 'Bio',
                            hint: 'Tell us about yourself...',
                            icon: Icons.edit_note_rounded,
                            maxLines: 3,
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Contact Section Card
                      _buildSectionCard(
                        title: 'Contact',
                        icon: Icons.contact_mail_outlined,
                        colorScheme: colorScheme,
                        textTheme: textTheme,
                        children: [
                          _buildEmailField(
                            colorScheme: colorScheme,
                            textTheme: textTheme,
                          ),
                          const SizedBox(height: 16),
                          _buildPhoneFieldWithVerification(
                            screenHeight: screenHeight,
                            screenWidth: screenWidth,
                            colorScheme: colorScheme,
                            textTheme: textTheme,
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Other Info Section Card
                      _buildSectionCard(
                        title: 'Other',
                        icon: Icons.info_outline_rounded,
                        colorScheme: colorScheme,
                        textTheme: textTheme,
                        children: [
                          _buildTextField(
                            controller: _occupationController,
                            label: 'Occupation',
                            hint: 'What do you do?',
                            icon: Icons.work_outline_rounded,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _ageController,
                            label: 'Age',
                            hint: 'Your age',
                            icon: Icons.cake_outlined,
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value != null && value.isNotEmpty) {
                                final age = int.tryParse(value);
                                if (age == null || age < 18 || age > 100) {
                                  return 'Please enter a valid age (18-100)';
                                }
                              }
                              return null;
                            },
                          ),
                        ],
                      ),

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

  // Modern section card with icon header
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with icon
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  // 📱 Phone field with verification button
  Widget _buildPhoneFieldWithVerification({
    required double screenHeight,
    required double screenWidth,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    final currentPhone = _phoneController.text.trim();
    final originalPhone = _originalPhone ?? '';
    final hasPhoneChanged = _normalizePhone(currentPhone) != _normalizePhone(originalPhone);
    final needsVerification = hasPhoneChanged && currentPhone.isNotEmpty;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.phone_rounded,
              size: 16,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Phone',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: '+91 XXXXX XXXXX',
                  hintStyle: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                    fontWeight: FontWeight.w400,
                  ),
                  suffixIcon: _phoneVerified && !hasPhoneChanged
                      ? Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.verified_rounded,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            if (needsVerification) ...[
              const SizedBox(width: 10),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: _isCheckingPhone ? null : _onVerifyPhonePressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.secondary,
                    foregroundColor: colorScheme.onSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    elevation: 0,
                  ),
                  child: _isCheckingPhone
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onSecondary,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_user_rounded, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'Verify',
                              style: textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSecondary,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (needsVerification)
          _buildInfoChip(
            icon: Icons.info_outline_rounded,
            text: 'New phone requires OTP verification',
            color: colorScheme.tertiary,
          )
        else if (_phoneVerified && currentPhone.isNotEmpty && !hasPhoneChanged)
          _buildInfoChip(
            icon: Icons.check_circle_rounded,
            text: 'Verified',
            color: colorScheme.primary,
          ),
      ],
    );
  }

  // Normalize phone number for comparison
  String _normalizePhone(String phone) {
    String normalized = phone.replaceAll(' ', '').replaceAll('-', '').replaceAll('(', '').replaceAll(')', '');
    if (normalized.startsWith('+91')) {
      normalized = normalized.substring(3);
    } else if (normalized.startsWith('91') && normalized.length > 10) {
      normalized = normalized.substring(2);
    }
    return normalized;
  }

  // Handle verify phone button press - uses existing OTP screen
  Future<void> _onVerifyPhonePressed() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a phone number'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    // Validate phone format (10 digits)
    final normalizedPhone = _normalizePhone(phone);
    if (normalizedPhone.length != 10 || !RegExp(r'^[0-9]+$').hasMatch(normalizedPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a valid 10-digit phone number'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isCheckingPhone = true);

    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('User not found');

      // Check if this is the user's own original phone number
      final originalPhone = _originalPhone ?? '';
      final isOwnPhone = _normalizePhone(phone) == _normalizePhone(originalPhone);

      // Only check if phone is taken when it's NOT the user's original phone
      if (!isOwnPhone) {
        final isTaken = await _firestoreService.isPhoneTaken(phone, user.uid);
        if (isTaken) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('❌ This phone number is already registered with another account'),
                backgroundColor: Theme.of(context).colorScheme.error,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      // Format phone number with country code
      String formattedPhone = phone.replaceAll(' ', '').replaceAll('-', '');
      if (!formattedPhone.startsWith('+')) {
        formattedPhone = '+91$formattedPhone';
      }

      // Send OTP using existing auth service
      await _authService.sendOTP(
        phoneNumber: formattedPhone,
        onCodeSent: (verificationId) async {
          if (mounted) {
            // Navigate to existing OTP screen with isPhoneUpdate flag
            final result = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (context) => OtpScreen(
                  verificationId: verificationId,
                  isPhoneUpdate: true, // This ensures it just verifies and returns
                ),
                settings: RouteSettings(arguments: formattedPhone),
              ),
            );

            // If user successfully verified (result == true from OTP screen)
            if (result == true && mounted) {
              final currentUser = FirebaseAuth.instance.currentUser;
              if (currentUser != null) {
                // Update phone in Firestore
                await _firestoreService.updateUserPhone(user.uid, formattedPhone);
                
                setState(() {
                  _phoneVerified = true;
                  _originalPhone = formattedPhone;
                  _phoneController.text = formattedPhone;
                });
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('✅ Phone number verified successfully!'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                );
              }
            }
          }
        },
        onFailed: (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to send OTP: ${error.message}'),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingPhone = false);
      }
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    bool readOnly = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          readOnly: readOnly,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withOpacity(0.5),
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.4),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: maxLines > 1 ? 12 : 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: colorScheme.outlineVariant.withOpacity(0.4),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: colorScheme.primary,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: colorScheme.error.withOpacity(0.8),
                width: 1,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: colorScheme.error,
                width: 1.5,
              ),
            ),
            errorStyle: textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  // Helper chip for status indicators
  Widget _buildInfoChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
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

  // Email field - shows different UI based on whether user has email or not
  Widget _buildEmailField({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    final currentEmail = _addedEmail ?? widget.currentUser.email;
    final hasEmail = currentEmail.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.mail_outline_rounded,
              size: 16,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Email',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (hasEmail) ...[
          // User has email - show compact locked field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.4),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    currentEmail,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                if ((FirebaseAuth.instance.currentUser?.emailVerified ?? false) ||
                    _addedEmail != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          color: colorScheme.primary,
                          size: 12,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Verified',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  Icons.lock_outline_rounded,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  size: 16,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Email cannot be changed for security',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ] else ...[
          // User has no email - show add button
          InkWell(
            onTap: _isAddingEmail ? null : _addEmailViaGoogle,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add email address',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_isAddingEmail)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/google_logo.png',
                          width: 18,
                          height: 18,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.g_mobiledata_rounded,
                              color: colorScheme.primary,
                              size: 20,
                            );
                          },
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.add_circle_rounded,
                          color: colorScheme.primary,
                          size: 18,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Link your Google account to add an email',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

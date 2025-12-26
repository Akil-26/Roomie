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

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final ImagePicker _imagePicker = ImagePicker();

  // Controllers for form fields
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _bioController;
  late TextEditingController _phoneController;
  late TextEditingController _occupationController;
  late TextEditingController _ageController;
  late TextEditingController _upiIdController;

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
    _upiIdController = TextEditingController(
      text: widget.currentUser.upiId ?? '',
    );
    _currentProfileImageUrl = widget.currentUser.profileImageUrl;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _occupationController.dispose();
    _ageController.dispose();
    _upiIdController.dispose();
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
        upiId: _upiIdController.text.trim().isEmpty
                ? null
                : _upiIdController.text.trim(),
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

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Edit Profile',
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.015,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isLoading ? null : _saveProfile,
              child:
                  _isLoading
                      ? SizedBox(
                        width: screenWidth * 0.04,
                        height: screenWidth * 0.04,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.onSurface,
                          ),
                        ),
                      )
                      : Text(
                        'Save',
                        style: textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(screenWidth * 0.05),
          child: Column(
            children: [
              // Header card with large profile image
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(screenWidth * 0.04),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          ProfileImageWidget(
                            imageUrl: _currentProfileImageUrl,
                            localPreviewFile: !kIsWeb ? _selectedImage : null,
                            radius: screenWidth * 0.2,
                            placeholder: Icon(
                              Icons.person,
                              size: screenWidth * 0.2,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                padding: EdgeInsets.all(screenWidth * 0.025),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.camera_alt,
                                  color: colorScheme.onPrimary,
                                  size: screenWidth * 0.045,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.015),
                    Text(
                      _selectedXFile != null || _selectedImage != null
                          ? 'New image selected'
                          : (_currentProfileImageUrl != null &&
                                  _currentProfileImageUrl!.isNotEmpty
                              ? 'Current profile image'
                              : 'No profile image'),
                      style: TextStyle(
                        color:
                            _selectedXFile != null || _selectedImage != null
                                ? colorScheme.secondary
                                : colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              SizedBox(height: screenHeight * 0.03),

              // Form Fields
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(screenWidth * 0.03),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Profile'),
                    SizedBox(height: screenHeight * 0.01),
                    _buildTextField(
                      controller: _usernameController,
                      label: 'Username',
                      hint: 'Enter your username',
                      icon: Icons.alternate_email,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Username is required';
                        }
                        return null;
                      },
                    ),

                    SizedBox(height: screenHeight * 0.015),

                    _buildTextField(
                      controller: _bioController,
                      label: 'Bio',
                      hint: 'Tell us about yourself',
                      icon: Icons.info_outline,
                      maxLines: 3,
                    ),

                    SizedBox(height: screenHeight * 0.015),
                    Divider(height: 16, color: colorScheme.outlineVariant),
                    SizedBox(height: screenHeight * 0.008),

                    _buildSectionTitle('Contact'),
                    SizedBox(height: screenHeight * 0.01),
                    
                    // Email field - conditional based on whether user has email
                    _buildEmailField(
                      colorScheme: colorScheme,
                      textTheme: textTheme,
                    ),

                    SizedBox(height: screenHeight * 0.015),
                    // Phone field with verification
                    _buildPhoneFieldWithVerification(
                      screenHeight: screenHeight,
                      screenWidth: screenWidth,
                      colorScheme: colorScheme,
                      textTheme: textTheme,
                    ),

                    SizedBox(height: screenHeight * 0.015),
                    _buildTextField(
                      controller: _upiIdController,
                      label: 'UPI ID (Optional)',
                      hint: 'username@bank (e.g., akil@ybl)',
                      icon: Icons.payment,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          if (!value.contains('@')) {
                            return 'Enter valid UPI ID (username@bank)';
                          }
                          // Check for valid format: something@something
                          final parts = value.split('@');
                          if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
                            return 'Invalid UPI ID format';
                          }
                        }
                        return null;
                      },
                    ),

                    SizedBox(height: screenHeight * 0.015),
                    Divider(height: 16, color: colorScheme.outlineVariant),
                    SizedBox(height: screenHeight * 0.008),

                    _buildSectionTitle('Other'),
                    SizedBox(height: screenHeight * 0.01),
                    _buildTextField(
                      controller: _occupationController,
                      label: 'Occupation',
                      hint: 'Enter your occupation',
                      icon: Icons.work_outline,
                    ),

                    SizedBox(height: screenHeight * 0.015),

                    _buildTextField(
                      controller: _ageController,
                      label: 'Age',
                      hint: 'Enter your age',
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
              ),

              SizedBox(height: screenHeight * 0.03),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(
            screenWidth * 0.05,
            0,
            screenWidth * 0.05,
            screenHeight * 0.02 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            width: double.infinity,
            height: screenHeight * 0.06,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _saveProfile,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isLoading
                  ? SizedBox(
                      width: screenWidth * 0.045,
                      height: screenWidth * 0.045,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                _isLoading ? 'Saving…' : 'Save changes',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onPrimary,
                ),
              ),
            ),
          ),
        ),
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
        Text(
          'Phone',
          style: textTheme.titleSmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: screenHeight * 0.01),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}), // Rebuild to show verify button
                decoration: InputDecoration(
                  hintText: 'Enter your phone number',
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                  prefixIcon: Icon(Icons.phone_outlined, color: colorScheme.onSurfaceVariant),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.primary),
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  // Show verification status
                  suffixIcon: _phoneVerified && !hasPhoneChanged
                      ? Tooltip(
                          message: 'Verified',
                          child: Icon(
                            Icons.verified,
                            color: colorScheme.primary,
                          ),
                        )
                      : null,
                ),
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                ),
              ),
            ),
            // Verify button if phone changed
            if (needsVerification) ...[
              SizedBox(width: screenWidth * 0.02),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isCheckingPhone ? null : _onVerifyPhonePressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.secondary,
                    foregroundColor: colorScheme.onSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.03),
                  ),
                  icon: _isCheckingPhone
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onSecondary,
                          ),
                        )
                      : const Icon(Icons.verified_user, size: 18),
                  label: Text(
                    _isCheckingPhone ? '...' : 'Verify',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
        // Helper text
        if (needsVerification)
          Padding(
            padding: EdgeInsets.only(top: screenHeight * 0.005),
            child: Text(
              '⚠️ New phone number requires OTP verification',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.tertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else if (_phoneVerified && currentPhone.isNotEmpty && !hasPhoneChanged)
          Padding(
            padding: EdgeInsets.only(top: screenHeight * 0.005),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 14, color: colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  'Verified',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
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

      // Check if phone is already taken by another user
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
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.titleSmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: screenHeight * 0.01),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          readOnly: readOnly,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
            prefixIcon: icon != null
                ? Icon(icon, color: colorScheme.onSurfaceVariant)
                : null,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.error),
            ),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
          ),
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return Text(
      title,
      style: textTheme.titleSmall?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  // Email field - shows different UI based on whether user has email or not
  Widget _buildEmailField({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    // Get current email - either original, newly added, or empty
    final currentEmail = _addedEmail ?? widget.currentUser.email;
    final hasEmail = currentEmail.isNotEmpty;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Email',
          style: textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        
        if (hasEmail) ...[
          // User HAS email - show locked read-only field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.mail_outline,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    currentEmail,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                // Verified badge - show if email is verified OR if it's newly added via Google
                if ((FirebaseAuth.instance.currentUser?.emailVerified ?? false) || _addedEmail != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified,
                          color: colorScheme.secondary,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Verified',
                          style: TextStyle(
                            color: colorScheme.secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Lock icon to show it's not editable
                const SizedBox(width: 8),
                Icon(
                  Icons.lock_outline,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  size: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              'Email cannot be changed for security reasons',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                fontSize: 11,
              ),
            ),
          ),
        ] else ...[
          // User has NO email - show "Add email" button
          InkWell(
            onTap: _isAddingEmail ? null : _addEmailViaGoogle,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.mail_outline,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
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
                      width: 20,
                      height: 20,
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
                          width: 20,
                          height: 20,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.g_mobiledata,
                              color: colorScheme.primary,
                              size: 24,
                            );
                          },
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.add_circle_outline,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              'Link your Google account to add an email',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

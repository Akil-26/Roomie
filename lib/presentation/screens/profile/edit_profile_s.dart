// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:roomie/data/datasources/firestore_service.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/models/user_model.dart';
import 'package:roomie/presentation/widgets/profile_image_widget.dart';
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

  File? _selectedImage;
  XFile? _selectedXFile; // For web compatibility
  bool _isLoading = false;
  String? _currentProfileImageUrl;
  bool _isSendingEmailVerification = false;
  bool _isCheckingEmailVerification = false;
  String? _pendingEmail; // email awaiting verification
  bool _emailVerified = false;

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
    _occupationController = TextEditingController(
      text: widget.currentUser.occupation ?? '',
    );
    _ageController = TextEditingController(
      text: widget.currentUser.age?.toString() ?? '',
    );
    _currentProfileImageUrl = widget.currentUser.profileImageUrl;
    _emailVerified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;

    // Clear pending state if user edits email away from the pending one
    _emailController.addListener(() {
      final pending = _pendingEmail;
      if (pending != null &&
          _emailController.text.trim().toLowerCase() != pending.toLowerCase()) {
        setState(() {
          _pendingEmail = null;
        });
      }
    });
  }

  @override
  void dispose() {
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

      // First save the profile with image (if new image selected)
      await _firestoreService.saveUserProfile(
        userId: user.uid,
        username: _usernameController.text.trim(),
        bio: _bioController.text.trim(),
        email: FirebaseAuth.instance.currentUser?.email ?? widget.currentUser.email,
        phone: _phoneController.text.trim(),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendEmailVerificationForUpdate() async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final newEmail = _emailController.text.trim();

    if (newEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter an email'),
          backgroundColor: colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // Basic email format check
    final emailRegex = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$");
    if (!emailRegex.hasMatch(newEmail)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a valid email'),
          backgroundColor: colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSendingEmailVerification = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw FirebaseAuthException(code: 'user-not-found');

      // Send verification depending on whether email changed or not
      final currentEmail = user.email ?? '';
      final actionCodeSettings = ActionCodeSettings(
        url: 'https://roomie-app.example.com/email-update',
        handleCodeInApp: false,
      );

      if (newEmail.toLowerCase() == currentEmail.toLowerCase()) {
        // Verify existing email
        await user.sendEmailVerification(actionCodeSettings);
      } else {
        // Verify before update to new email
        await user.verifyBeforeUpdateEmail(newEmail, actionCodeSettings);
      }

      setState(() {
        _pendingEmail = newEmail;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification link sent to $newEmail'),
          backgroundColor: colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Failed to send verification';
      if (e.code == 'requires-recent-login') {
        message = 'Please re-login to change your email.';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address.';
      } else if (e.code == 'email-already-in-use') {
        message = 'Email already in use.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingEmailVerification = false);
    }
  }

  Future<void> _checkEmailVerificationStatus() async {
    final colorScheme = Theme.of(context).colorScheme;
    setState(() => _isCheckingEmailVerification = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw FirebaseAuthException(code: 'user-not-found');
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed != null) {
        final updatedEmail = refreshed.email ?? '';
        final verified = refreshed.emailVerified;
        if (_pendingEmail != null && updatedEmail.toLowerCase() == _pendingEmail!.toLowerCase() && verified) {
          setState(() {
            _emailController.text = updatedEmail;
            _pendingEmail = null;
            _emailVerified = true;
          });
          // Sync the new verified email to Firestore profile immediately
          try {
            await _firestoreService.saveUserDetails(refreshed.uid, updatedEmail);
          } catch (_) {}
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Email verified and updated!'),
              backgroundColor: colorScheme.secondary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Not verified yet. Please check your inbox."),
              backgroundColor: colorScheme.onSurfaceVariant,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error checking verification: $e'),
          backgroundColor: colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCheckingEmailVerification = false);
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
          TextButton(
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
                    _buildTextField(
                      controller: _emailController,
                      label: 'Email',
                      hint: 'Your email address',
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                      readOnly: false,
                    ),

                    SizedBox(height: screenHeight * 0.01),
                    Builder(
                      builder: (context) {
                        final currentAuth = FirebaseAuth.instance.currentUser;
                        final matchesAuthEmail =
                            (currentAuth?.email ?? '').toLowerCase() ==
                            _emailController.text.trim().toLowerCase();
                        final isVerified = currentAuth?.emailVerified ?? false;

                        final shouldShowVerifyRow =
                            _pendingEmail != null || !isVerified || !matchesAuthEmail;
                        if (!shouldShowVerifyRow) return const SizedBox.shrink();

                        final isEmailChanged = !matchesAuthEmail;
                        final buttonLabel = isEmailChanged
                            ? 'Verify & Update'
                            : 'Send verification';

                        return Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isSendingEmailVerification
                                    ? null
                                    : _sendEmailVerificationForUpdate,
                                icon: _isSendingEmailVerification
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            colorScheme.primary,
                                          ),
                                        ),
                                      )
                                    : const Icon(Icons.mark_email_read_outlined),
                                label: Text(buttonLabel),
                              ),
                            ),
                            SizedBox(width: screenWidth * 0.03),
                            if (_pendingEmail != null)
                              TextButton(
                                onPressed: _isCheckingEmailVerification
                                    ? null
                                    : _checkEmailVerificationStatus,
                                child: _isCheckingEmailVerification
                                    ? const Text('Checking…')
                                    : const Text("I've verified"),
                              ),
                          ],
                        );
                      },
                    ),
                    SizedBox(height: screenHeight * 0.008),
                    Builder(
                      builder: (context) {
                        final currentAuth = FirebaseAuth.instance.currentUser;
                        final matchesAuthEmail =
                            (currentAuth?.email ?? '').toLowerCase() ==
                            _emailController.text.trim().toLowerCase();
                        if (_emailVerified && matchesAuthEmail) {
                          return Row(
                            children: [
                              Icon(Icons.verified, color: colorScheme.tertiary, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'Verified',
                                style: TextStyle(
                                  color: colorScheme.tertiary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          );
                        } else if (_pendingEmail != null) {
                          return Row(
                            children: [
                              Icon(Icons.schedule, color: colorScheme.onSurfaceVariant, size: 18),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Verification sent to $_pendingEmail. Open email to confirm.',
                                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          );
                        } else {
                          return const SizedBox.shrink();
                        }
                      },
                    ),

                    SizedBox(height: screenHeight * 0.015),
                    _buildTextField(
                      controller: _phoneController,
                      label: 'Phone',
                      hint: 'Enter your phone number',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
}

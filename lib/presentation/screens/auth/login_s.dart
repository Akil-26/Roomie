import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/firestore_service.dart';
import 'package:roomie/presentation/widgets/roomie_loading_widget.dart';
import 'package:roomie/presentation/screens/auth/otp_s.dart';
import 'package:roomie/presentation/screens/profile/user_details_s.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phoneController = TextEditingController();
  bool _loading = false;

  void _sendOTP() async {
    String phone = _phoneController.text.trim();
    if (!phone.startsWith('+91')) {
      phone = '+91$phone';
    }

    setState(() => _loading = true);

    /// ✅ Send OTP for all users (new or existing)
    await AuthService().sendOTP(
      phoneNumber: phone,
      onCodeSent: (verificationId) {
        setState(() => _loading = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtpScreen(verificationId: verificationId),
            settings: RouteSettings(arguments: phone), // Pass phone number here
          ),
        );
      },
      onFailed: (e) {
        setState(() => _loading = false);
        _showCustomSnackBar(
          context,
          'Phone Auth Error: ${e.message}',
          isError: true,
        );
      },
    );
  }

  /// ✅ Smart Google Authentication - Single button for all users
  Future<void> _continueWithGoogle() async {
    setState(() => _loading = true);
    final authService = AuthService();

    try {
      print('🔄 Login: Starting Google authentication...');
      final result = await authService.signInWithGoogle();

      if (!mounted) return;

      setState(() => _loading = false);

      print('🔄 Google auth result: ${result.status}');

      switch (result.status) {
        case GoogleSignInStatus.success:
          print('✅ Google auth successful, handling user...');
          await _handleGoogleAuthSuccess(result.user);
          break;
        case GoogleSignInStatus.cancelled:
        case GoogleSignInStatus.popupClosed:
          print('🚫 Google auth cancelled by user');
          if (mounted) {
            _showCustomSnackBar(
              context,
              'Sign-in was cancelled. Please try again.',
              isWarning: true,
            );
          }
          break;
        case GoogleSignInStatus.error:
          print('🚨 Google auth error: ${result.message}');
          if (mounted) {
            _showCustomSnackBar(
              context,
              'Authentication failed: ${result.message ?? 'Unknown error'}',
              isError: true,
            );
          }
          break;
      }
    } catch (e) {
      print('🚨 Exception in Google auth: $e');
      if (mounted) {
        setState(() => _loading = false);
        _showCustomSnackBar(context, 'Authentication error: $e', isError: true);
      }
      return;
    }
  }

  /// ✅ Smart routing logic based on user profile completion
  Future<void> _handleGoogleAuthSuccess(User? user) async {
    if (user == null) {
      print('🚨 No user returned from Google auth');
      _showCustomSnackBar(
        context,
        'Authentication error: No user returned',
        isError: true,
      );
      return;
    }

    print('🔄 Checking user profile for: ${user.email} (${user.uid})');
    final userDetails = await FirestoreService().getUserDetails(user.uid);
    if (!mounted) return;

    print('🔍 User details found: $userDetails');

    if (userDetails == null ||
        userDetails['username'] == null ||
        userDetails['username'].toString().isEmpty) {
      // ✅ New user or incomplete profile - go to user details page
      print('📝 New user detected - navigating to User Details');
      _showCustomSnackBar(
        context,
        'Welcome ${user.displayName ?? user.email}! Please complete your profile.',
        isSuccess: true,
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => UserDetailsScreen(isFromPhoneSignup: false),
        ),
      );
    } else {
      // ✅ Existing user with complete profile - go directly to home
      print('🏠 Existing user detected - going to Home');
      _showCustomSnackBar(
        context,
        'Welcome back, ${userDetails['username']}!',
        isSuccess: true,
      );
      Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
    }
  }

  void _showCustomSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isSuccess = false,
    bool isWarning = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color backgroundColor;
    Color textColor;
    IconData icon;

    if (isError) {
      backgroundColor = colorScheme.error;
      textColor = colorScheme.onError;
      icon = Icons.error_outline;
    } else if (isSuccess) {
      backgroundColor = colorScheme.secondary;
      textColor = colorScheme.onSecondary;
      icon = Icons.check_circle_outline;
    } else if (isWarning) {
      backgroundColor = colorScheme.tertiaryContainer;
      textColor = colorScheme.onTertiaryContainer;
      icon = Icons.warning_amber_outlined;
    } else {
      backgroundColor = colorScheme.primaryContainer;
      textColor = colorScheme.onPrimaryContainer;
      icon = Icons.info_outline;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: textColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        elevation: 8,
        action: SnackBarAction(
          label: 'OK',
          textColor: textColor,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + screenHeight * 0.02,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          top: screenHeight * 0.025,
                          left: screenWidth * 0.125,
                          right: screenWidth * 0.02,
                          bottom: screenHeight * 0.01,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Welcome To Roomie',
                                textAlign: TextAlign.center,
                                style: textTheme.headlineMedium?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.015,
                                ),
                              ),
                            ),
                            SizedBox(width: screenWidth * 0.12),
                          ],
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.01),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.04,
                          vertical: screenHeight * 0.015,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                style: textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Phone number',
                                  filled: true,
                                  fillColor:
                                      colorScheme.surfaceContainerHighest,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: screenHeight * 0.022,
                                    horizontal: screenWidth * 0.04,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                      color: colorScheme.outlineVariant,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                      color: colorScheme.primary,
                                      width: 1.5,
                                    ),
                                  ),
                                  hintStyle: textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _sendOTP,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              minimumSize: Size.fromHeight(screenHeight * 0.065),
                              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.017),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(32),
                              ),
                              elevation: 1,
                              shadowColor: colorScheme.primary.withValues(
                                alpha: 0.25,
                              ),
                            ),
                            child:
                                _loading
                                    ? RoomieLoadingSmall(size: screenWidth * 0.06)
                                    : Text(
                                      'Sign up with Phone',
                                      style: textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onPrimary,
                                        letterSpacing: 0.015,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.04,
                          vertical: screenHeight * 0.01,
                        ),
                        child: Text(
                          'Or continue with Google',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.04,
                          vertical: screenHeight * 0.015,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _loading ? null : _continueWithGoogle,
                            icon: Icon(
                              Icons.g_mobiledata,
                              color: colorScheme.onSecondary,
                              size: screenWidth * 0.06,
                            ),
                            label: Text(
                              'Continue with Google',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSecondary,
                                letterSpacing: 0.015,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.secondary,
                              foregroundColor: colorScheme.onSecondary,
                              minimumSize: Size.fromHeight(screenHeight * 0.065),
                              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.017),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(32),
                              ),
                              elevation: 2,
                              shadowColor: colorScheme.secondary.withValues(
                                alpha: 0.25,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
                        child: Text(
                          'By continuing, you agree to our Terms of Service and Privacy Policy',
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.025),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

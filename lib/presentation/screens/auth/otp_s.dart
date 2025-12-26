import 'dart:async';
import 'package:flutter/material.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/firestore_service.dart';
import 'package:roomie/presentation/widgets/roomie_loading_widget.dart';
import 'package:roomie/presentation/screens/profile/user_details_s.dart';

class OtpScreen extends StatefulWidget {
  final String verificationId;
  final bool isPhoneUpdate; // true = just verify & return, false = sign in flow

  const OtpScreen({
    super.key, 
    required this.verificationId,
    this.isPhoneUpdate = false,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  final List<TextEditingController> _digitControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _loading = false;
  int _secondsRemaining = 30;
  late final Timer _timer;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _secondsRemaining = 30;
    _canResend = false;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        setState(() {
          _canResend = true;
        });
        _timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _resendOTP() {
    _startTimer();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('OTP resent!')));
  }

  void _verifyOTP() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit OTP')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // For phone update mode - just verify OTP and return true
      if (widget.isPhoneUpdate) {
        // Verify OTP credential without signing in
        final credential = await AuthService().verifyOTPOnly(
          verificationId: widget.verificationId,
          smsCode: otp,
        );
        
        if (credential) {
          if (mounted) {
            Navigator.pop(context, true); // Return true = verified successfully
          }
        } else {
          throw Exception('Invalid OTP');
        }
        return;
      }

      // Normal sign-in flow
      final user = await AuthService().signInWithOTP(
        verificationId: widget.verificationId,
        smsCode: otp,
      );

      if (user != null) {
        final userDetails = await FirestoreService().getUserDetails(user.uid);
        if (mounted) {
          if (userDetails == null ||
              userDetails['username'] == null ||
              userDetails['username'].toString().isEmpty) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder:
                    (_) => const UserDetailsScreen(isFromPhoneSignup: true),
              ),
            );
          } else {
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/home',
              (route) => false,
            );
          }
        }
      } else {
        throw Exception('Failed to sign in with OTP.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OTP Verification Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final phoneNumber = ModalRoute.of(context)?.settings.arguments as String?;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: screenHeight * 0.025),
              // Header with back button
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: EdgeInsets.all(screenWidth * 0.02),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.onSurface.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        size: screenWidth * 0.045,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.05),

              // Title and description
              Text(
                'Enter verification code',
                style: textTheme.headlineSmall?.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: screenHeight * 0.015),
              Text(
                phoneNumber != null
                    ? 'We\'ve sent a code to $phoneNumber'
                    : 'We\'ve sent a verification code to your phone',
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: 16,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              SizedBox(height: screenHeight * 0.075),

              // OTP input boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  return Container(
                    width: screenWidth * 0.1125,
                    height: screenHeight * 0.062,
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _digitControllers[index],
                      focusNode: _focusNodes[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      style: textTheme.titleMedium?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintStyle: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          if (index < 5) {
                            _focusNodes[index + 1].requestFocus();
                          } else {
                            _focusNodes[index].unfocus();
                          }
                        } else if (value.isEmpty && index > 0) {
                          _focusNodes[index - 1].requestFocus();
                        }
                        // Update the main OTP controller
                        String otp =
                            _digitControllers.map((c) => c.text).join();
                        _otpController.text = otp;
                        setState(() {});
                      },
                      onTap: () {
                        _focusNodes[index].requestFocus();
                      },
                    ),
                  );
                }),
              ),

              const Spacer(),

              // Resend code section
              Center(
                child:
                    _canResend
                        ? TextButton(
                          onPressed: _resendOTP,
                          child: Text(
                            'Resend code',
                            style: textTheme.bodyMedium?.copyWith(
                              fontSize: 16,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                        : Text(
                          'Resend code in 00:${_secondsRemaining.toString().padLeft(2, '0')}',
                          style: textTheme.bodyMedium?.copyWith(
                            fontSize: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
              ),

              SizedBox(height: screenHeight * 0.04),

              // Verify button
              SizedBox(
                width: double.infinity,
                height: screenHeight * 0.062,
                child: ElevatedButton(
                  onPressed: _loading ? null : _verifyOTP,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child:
                      _loading
                          ? SizedBox(
                            width: screenWidth * 0.06,
                            height: screenWidth * 0.06,
                            child: RoomieLoadingSmall(size: screenWidth * 0.06),
                          )
                          : const Text(
                            'Verify',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

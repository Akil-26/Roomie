import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:roomie/data/datasources/phone_verification_service.dart';
import 'package:roomie/data/datasources/auth_service.dart';

/// Screen for verifying phone number with OTP
class PhoneVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String? verificationId;
  final bool isFromPaymentRequest;

  const PhoneVerificationScreen({
    super.key,
    required this.phoneNumber,
    this.verificationId,
    this.isFromPaymentRequest = false,
  });

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final PhoneVerificationService _phoneService = PhoneVerificationService();
  final AuthService _authService = AuthService();
  final TextEditingController _otpController = TextEditingController();
  final List<TextEditingController> _otpDigitControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  String? _verificationId;
  bool _isLoading = false;
  bool _isResending = false;
  String? _errorMessage;
  int _resendCountdown = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    
    // If no verification ID provided, start verification
    if (_verificationId == null) {
      _startPhoneVerification();
    } else {
      _startResendCountdown();
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    for (var controller in _otpDigitControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startResendCountdown() {
    setState(() {
      _resendCountdown = 60;
      _canResend = false;
    });

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _resendCountdown > 0) {
        setState(() {
          _resendCountdown--;
        });
        if (_resendCountdown > 0) {
          _startResendCountdown();
        } else {
          setState(() {
            _canResend = true;
          });
        }
      }
    });
  }

  Future<void> _startPhoneVerification() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _phoneService.startPhoneVerification(
        phoneNumber: widget.phoneNumber,
        onVerificationCompleted: (PhoneAuthCredential credential) async {
          // Auto verification completed
          final userId = _authService.currentUser?.uid;
          if (userId != null) {
            await _phoneService.markPhoneVerified(userId);
            if (mounted) {
              _showSuccess('Phone verified successfully!');
              Navigator.of(context).pop(true);
            }
          }
        },
        onVerificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() {
              _errorMessage = e.message ?? 'Verification failed';
              _isLoading = false;
            });
          }
        },
        onCodeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _isLoading = false;
            });
            _startResendCountdown();
          }
        },
        onCodeAutoRetrievalTimeout: (String verificationId) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to send verification code: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpDigitControllers.map((c) => c.text).join();
    
    if (otp.length != 6) {
      setState(() {
        _errorMessage = 'Please enter complete OTP';
      });
      return;
    }

    if (_verificationId == null) {
      setState(() {
        _errorMessage = 'Verification ID not found. Please resend code.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      setState(() {
        _errorMessage = 'User not authenticated';
        _isLoading = false;
      });
      return;
    }

    try {
      final success = await _phoneService.verifyOtpCode(
        verificationId: _verificationId!,
        smsCode: otp,
        userId: userId,
      );

      if (mounted) {
        if (success) {
          _showSuccess('✅ Phone verified successfully!');
          Navigator.of(context).pop(true); // Return success
        } else {
          setState(() {
            _errorMessage = 'Invalid OTP. Please try again.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Verification failed: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      await _startPhoneVerification();
      if (mounted) {
        _showSuccess('New code sent to ${widget.phoneNumber}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Phone Number'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              
              // Icon
              Icon(
                Icons.phone_android,
                size: 80,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 32),
              
              // Title
              Text(
                'Enter Verification Code',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              // Subtitle
              Text(
                'We sent a 6-digit code to',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                widget.phoneNumber,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              
              // OTP Input Fields
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 45,
                    child: TextField(
                      controller: _otpDigitControllers[index],
                      focusNode: _focusNodes[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty && index < 5) {
                          _focusNodes[index + 1].requestFocus();
                        } else if (value.isEmpty && index > 0) {
                          _focusNodes[index - 1].requestFocus();
                        }
                        
                        // Auto verify when all digits entered
                        if (index == 5 && value.isNotEmpty) {
                          _verifyOtp();
                        }
                      },
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              
              // Error Message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.red,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 24),
              
              // Verify Button
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Text(
                        'VERIFY',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 24),
              
              // Resend Code
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Didn't receive code? ",
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_canResend)
                    TextButton(
                      onPressed: _isResending ? null : _resendOtp,
                      child: _isResending
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'RESEND',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    )
                  else
                    Text(
                      'Resend in ${_resendCountdown}s',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              
              const Spacer(),
              
              // Info Text
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Phone verification is required for payment requests',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
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
    );
  }
}

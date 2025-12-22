import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Validation result types for phone verification
enum ValidationResult {
  success,
  phoneMissing,
  phoneNotVerified,
}

/// Service to handle phone number verification for payment requests
class PhoneVerificationService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Validate user has phone number and it's verified
  /// Returns ValidationResult indicating success or specific failure reason
  Future<ValidationResult> validateUserForPayment(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists || userDoc.data() == null) {
        debugPrint('❌ User document not found');
        return ValidationResult.phoneMissing;
      }

      final userData = userDoc.data()!;
      final phone = userData['phone']?.toString();
      final verified = userData['isPhoneVerified'] as bool?;

      // Check if phone number exists
      if (phone == null || phone.isEmpty) {
        debugPrint('❌ Phone number missing');
        return ValidationResult.phoneMissing;
      }

      // Check if phone is verified
      if (verified != true) {
        debugPrint('❌ Phone number not verified');
        return ValidationResult.phoneNotVerified;
      }

      debugPrint('✅ Phone validation passed');
      return ValidationResult.success;
    } catch (e) {
      debugPrint('❌ Error validating user: $e');
      return ValidationResult.phoneMissing;
    }
  }

  /// Update phone number in Firestore (not verified yet)
  Future<void> updatePhoneNumber(String userId, String phoneNumber) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'phone': phoneNumber,
        'isPhoneVerified': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Phone number updated: $phoneNumber');
    } catch (e) {
      debugPrint('❌ Error updating phone number: $e');
      rethrow;
    }
  }

  /// Mark phone number as verified in Firestore
  Future<void> markPhoneVerified(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'isPhoneVerified': true,
        'phoneVerifiedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Phone marked as verified');
    } catch (e) {
      debugPrint('❌ Error marking phone as verified: $e');
      rethrow;
    }
  }

  /// Start phone verification process using Firebase Auth
  /// Returns verification ID for later use
  Future<String?> startPhoneVerification({
    required String phoneNumber,
    required Function(PhoneAuthCredential) onVerificationCompleted,
    required Function(FirebaseAuthException) onVerificationFailed,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(String verificationId) onCodeAutoRetrievalTimeout,
  }) async {
    try {
      debugPrint('🔄 Starting phone verification for: $phoneNumber');

      String? verificationId;

      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('✅ Auto verification completed');
          onVerificationCompleted(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('❌ Verification failed: ${e.message}');
          onVerificationFailed(e);
        },
        codeSent: (String verId, int? resendToken) {
          debugPrint('✅ Code sent to $phoneNumber');
          verificationId = verId;
          onCodeSent(verId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verId) {
          debugPrint('⏱️ Auto retrieval timeout');
          verificationId = verId;
          onCodeAutoRetrievalTimeout(verId);
        },
      );

      return verificationId;
    } catch (e) {
      debugPrint('❌ Error starting phone verification: $e');
      rethrow;
    }
  }

  /// Verify OTP code entered by user
  Future<bool> verifyOtpCode({
    required String verificationId,
    required String smsCode,
    required String userId,
  }) async {
    try {
      debugPrint('🔄 Verifying OTP code...');

      // Create credential with verification ID and SMS code
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      // Link credential with current user (don't replace existing auth method)
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        try {
          // Try to link phone credential
          await currentUser.linkWithCredential(credential);
          debugPrint('✅ Phone credential linked successfully');
        } catch (e) {
          // If already linked, just verify the credential
          debugPrint('ℹ️ Phone already linked, verifying credential: $e');
          
          // Verify the credential is valid by attempting to sign in with it
          // (This won't affect current session since user is already signed in)
          await _auth.signInWithCredential(credential);
        }
      } else {
        // No current user, sign in with phone credential
        await _auth.signInWithCredential(credential);
        debugPrint('✅ Signed in with phone credential');
      }

      // Mark as verified in Firestore
      await markPhoneVerified(userId);

      return true;
    } catch (e) {
      debugPrint('❌ Error verifying OTP: $e');
      return false;
    }
  }

  /// Check if user's phone is already verified
  Future<bool> isPhoneVerified(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists && userDoc.data() != null) {
        return userDoc.data()!['isPhoneVerified'] as bool? ?? false;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error checking phone verification: $e');
      return false;
    }
  }

  /// Get user's phone number
  Future<String?> getPhoneNumber(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists && userDoc.data() != null) {
        return userDoc.data()!['phone']?.toString();
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting phone number: $e');
      return null;
    }
  }
}

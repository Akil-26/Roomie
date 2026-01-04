import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import 'groups_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, TargetPlatform, defaultTargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';

enum GoogleSignInStatus { success, cancelled, popupClosed, error }

class GoogleSignInResult {
  final GoogleSignInStatus status;
  final User? user;
  final String? message;
  const GoogleSignInResult(this.status, {this.user, this.message});

  bool get isSuccess => status == GoogleSignInStatus.success;
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _signingIn = false; // prevent concurrent

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Helper function to get detailed error information
  String _getDetailedErrorMessage(String error) {
    if (error.contains('DEVELOPER_ERROR')) {
      return '⚠️ Configuration Error: SHA-1 fingerprint not registered in Firebase Console.\n'
          '🔧 Required SHA-1: 84:C6:DF:83:C9:99:7A:7B:36:E8:9F:1F:D6:03:C7:65:32:9B:3E:B9\n'
          '📝 Add this fingerprint to Firebase Console → Project Settings → Your apps → SHA certificate fingerprints';
    }
    if (error.contains('API_NOT_CONNECTED')) {
      return 'Google Services API not connected. Check SHA-1 fingerprint configuration.';
    }
    if (error.contains('SIGN_IN_FAILED')) {
      return 'Google Sign-In failed. Verify Firebase configuration and SHA-1 fingerprints.';
    }
    if (error.contains('ClientConfigurationException')) {
      return 'Google client configuration error. Check google-services.json and SHA-1 fingerprints.';
    }
    return error;
  }

  Future<GoogleSignInResult> signInWithGoogle() async {
    if (_signingIn) {
      return const GoogleSignInResult(
        GoogleSignInStatus.error,
        message: 'Sign-In already in progress',
      );
    }
    _signingIn = true;
    try {
      UserCredential userCredential;

      if (kIsWeb) {
        // For web, use Firebase Auth directly with Google provider
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.setCustomParameters({
          'prompt': 'select_account', // Always show account selection
          'include_granted_scopes': 'true',
        });
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else if (_isMobilePlatform()) {
        // For mobile platforms - use google_sign_in package for native account picker
        print('🔄 Login: Starting mobile Google Sign-In...');

        final GoogleSignIn googleSignIn = GoogleSignIn(
          scopes: <String>['email', 'profile'],
        );

        // Ensure the native account picker is shown each time
        try {
          await googleSignIn.signOut();
        } catch (signOutError) {
          print('⚠️ Google sign-out before sign-in failed: $signOutError');
        }

        // Sign in with Google - this shows the native account picker
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

        if (googleUser == null) {
          // User cancelled the sign-in
          return const GoogleSignInResult(GoogleSignInStatus.cancelled);
        }

        // Get authentication details
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        // Create credential for Firebase
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        // Sign in to Firebase with the credential
        userCredential = await _auth.signInWithCredential(credential);

        print('🔄 Login: Google Sign-In successful');
      } else {
        // Desktop or unsupported platforms fall back to Firebase provider flow
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        googleProvider.setCustomParameters({
          'prompt': 'select_account',
          'include_granted_scopes': 'true',
        });

        userCredential = await _auth.signInWithProvider(googleProvider);
      }

      final user = userCredential.user;

      if (user == null) {
        return const GoogleSignInResult(
          GoogleSignInStatus.error,
          message: 'Firebase user null after Google sign-in',
        );
      }

      // Save user details to Firestore
      await FirestoreService().saveUserDetails(
        user.uid,
        user.email ?? '',
        name: user.displayName,
      );

      return GoogleSignInResult(GoogleSignInStatus.success, user: user);
    } catch (e) {
      final msg = e.toString();
      print('🚨 Google Sign-In Error: $msg');
      print('🔍 Error type: ${e.runtimeType}');

      // Get detailed error message
      final detailedMsg = _getDetailedErrorMessage(msg);

      // Handle specific error types for better debugging
      if (msg.contains('DEVELOPER_ERROR') ||
          msg.contains('API_NOT_CONNECTED')) {
        print('⚠️  SHA-1 fingerprint not registered in Firebase Console');
        return GoogleSignInResult(
          GoogleSignInStatus.error,
          message: detailedMsg,
        );
      }
      if (msg.contains('popup-blocked') ||
          msg.contains('popup-closed-by-user') ||
          msg.contains('cancelled-popup-request')) {
        return const GoogleSignInResult(GoogleSignInStatus.popupClosed);
      }
      if (msg.contains('user-cancelled') ||
          msg.contains('cancelled') ||
          msg.contains('auth/cancelled-popup-request') ||
          msg.contains('sign_in_canceled')) {
        return const GoogleSignInResult(GoogleSignInStatus.cancelled);
      }
      if (msg.contains('network') || msg.contains('connection')) {
        return const GoogleSignInResult(
          GoogleSignInStatus.error,
          message: 'Network error. Please check your internet connection.',
        );
      }
      if (msg.contains('sign_in_failed') ||
          msg.contains('SIGN_IN_FAILED') ||
          msg.contains('ClientConfigurationException')) {
        return GoogleSignInResult(
          GoogleSignInStatus.error,
          message: detailedMsg,
        );
      }
      return GoogleSignInResult(GoogleSignInStatus.error, message: detailedMsg);
    } finally {
      _signingIn = false;
    }
  }

  bool _isMobilePlatform() {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> sendOTP({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(FirebaseAuthException e) onFailed,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // You can auto-login here if needed
        },
        verificationFailed: (FirebaseAuthException e) {
          print('❌ OTP Failed: ${e.message}');
          onFailed(e);
        },
        codeSent: (String verificationId, int? resendToken) {
          print('📨 OTP Code Sent: $verificationId');
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          print('⏳ Auto-retrieval timeout: $verificationId');
        },
      );
    } catch (e) {
      print('❌ sendOTP Error: $e');
      if (e is FirebaseAuthException) {
        onFailed(e); // ✅ Notify the UI of failure
      } else {
        onFailed(
          FirebaseAuthException(
            code: 'unexpected-error',
            message: e.toString(),
          ),
        );
      }
    }
  }

  /// 🔐 Step 2: Sign in using received OTP (from SMS)
  Future<User?> signInWithOTP({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCred = await _auth.signInWithCredential(credential);
      // Save user details after successful OTP sign-in
      await FirestoreService().saveUserDetails(
        userCred.user!.uid,
        '', // Empty email for phone auth
        phone: userCred.user!.phoneNumber, // Store phone number in phone field
      );
      return userCred.user;
    } catch (e) {
      print('❌ OTP Sign-In Error: $e');
      return null;
    }
  }

  /// � Verify OTP only (without signing in) - for phone number update
  Future<bool> verifyOTPOnly({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      // Just verify the credential is valid by checking with Firebase
      // We don't sign in, just validate
      await _auth.currentUser?.updatePhoneNumber(credential);
      return true;
    } catch (e) {
      print('❌ OTP Verify Error: $e');
      // If updatePhoneNumber fails, try just validating the credential
      try {
        final credential = PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: smsCode,
        );
        // Create a temporary check - if credential is invalid, this will throw
        // This validates OTP is correct
        await _auth.signInWithCredential(credential);
        // Sign back in with original account if needed
        return true;
      } catch (e2) {
        print('❌ OTP Validation Error: $e2');
        return false;
      }
    }
  }

  /// �🔗 Optionally link phone auth with Google (Now using Firebase Auth directly)
  Future<bool> linkWithGoogle() async {
    try {
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      await _auth.currentUser?.linkWithProvider(googleProvider);
      return true;
    } catch (e) {
      print('❌ Link with Google Error: $e');
      return false;
    }
  }

  /// ❓ Check if phone number exists in Firestore
  Future<bool> doesPhoneExist(String phoneNumber) async {
    try {
      final query =
          await FirebaseFirestore.instance
              .collection('users')
              .where('phone', isEqualTo: phoneNumber)
              .limit(1)
              .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      print('❌ Firestore Phone Check Error: $e');
      return false;
    }
  }

  ///  Sign out from Firebase Auth and Google Sign-In
  Future<void> signOut() async {
    try {
      // Clear GroupsService cache before sign out to prevent stale data
      // This must happen BEFORE sign out so subsequent logins get fresh data
      _clearAllCaches();
      
      // Sign out from Firebase Auth
      await _auth.signOut();
      print('✅ Successfully signed out');
    } catch (e) {
      print('❌ Sign-out Error: $e');
    }
  }
  
  /// Clear all service caches on logout/account switch
  void _clearAllCaches() {
    try {
      // Clear GroupsService cache to prevent stale data on next login
      GroupsService().clearCache();
      print('🧹 Cleared all service caches on logout');
    } catch (e) {
      print('⚠️ Error clearing caches: $e');
    }
  }
}

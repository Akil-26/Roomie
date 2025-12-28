import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:roomie/data/datasources/profile_image_service.dart';
import 'package:roomie/data/datasources/profile_image_notifier.dart';

class FirestoreService {
  final _firestore = FirebaseFirestore.instance;
  final _profileImageService = ProfileImageService();
  final _profileImageNotifier = ProfileImageNotifier();

  // Get profile image (now just returns URL if already a URL)
  Future<String?> getProfileImage(String imageUrlOrId) async {
    try {
      return await _profileImageService.getUserProfileImage(imageUrlOrId);
    } catch (e) {
      print('Error getting profile image: $e');
      return null;
    }
  }

  /// Save or update user details
  Future<void> saveUserDetails(
    String uid,
    String email, {
    String? name,
    String? phone,
    String? username,
  }) async {
    final docRef = _firestore.collection('users').doc(uid);

    final userData = {
      'email': email,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (username != null) 'username': username,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) {
      // If new user, also store createdAt
      userData['createdAt'] = FieldValue.serverTimestamp();
    }

    await docRef.set(userData, SetOptions(merge: true));
  }

  /// Save user profile with username, bio, and profile image
  Future<void> saveUserProfile({
    required String userId,
    required String username,
    required String bio,
    required String email,
    required String phone,
    dynamic profileImage, // Can be File, XFile, or null
    String? occupation,
    int? age,
  }) async {
    final docRef = _firestore.collection('users').doc(userId);

    // 🔒 SECURITY: Check if email already exists for a different user
    if (email.isNotEmpty) {
      final emailQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .get();

      for (final doc in emailQuery.docs) {
        // Allow user to keep their own email, but reject if it belongs to someone else
        if (doc.id != userId) {
          throw Exception('This email already exists in Roomie. Please use a different email.');
        }
      }
    }

    // 🔒 SECURITY: Check if phone already exists for a different user
    if (phone.isNotEmpty) {
      final isTaken = await isPhoneTaken(phone, userId);
      if (isTaken) {
        throw Exception('This phone number already exists in Roomie. Please use a different number.');
      }
    }

    // Get existing data to preserve profile image URL if no new image is provided
    final docSnapshot = await docRef.get();
    String? existingProfileImageUrl;
    if (docSnapshot.exists) {
      final data = docSnapshot.data();
      existingProfileImageUrl = data?['profileImageUrl'] as String?;
    }

    String? profileImageUrl =
        existingProfileImageUrl; // Start with existing URL

    // Upload to Cloudinary if new file provided
    if (profileImage != null) {
      try {
        print('Uploading profile image to Cloudinary...');
        // Test connection first
        _profileImageService.testCloudinaryConnection();

        final uploadedUrl = await _profileImageService.saveUserProfileImage(
          userId: userId,
          imageFile: profileImage,
          previousImageId: existingProfileImageUrl,
        );
        if (uploadedUrl != null) {
          profileImageUrl = uploadedUrl;
          _profileImageNotifier.updateProfileImage(uploadedUrl);
          print('Profile image uploaded to Cloudinary: $uploadedUrl');
        } else {
          print('Cloudinary upload failed; keeping existing image');
        }
      } catch (e) {
        print('Error uploading profile image to Cloudinary: $e');
      }
    }

    final userData = {
      'username': username,
      'bio': bio,
      'email': email.toLowerCase(), // Always save email in lowercase for consistency
      'phone': phone,
      'profileImageUrl': profileImageUrl, // Always include this field
      if (occupation != null) 'occupation': occupation,
      if (age != null) 'age': age,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!docSnapshot.exists) {
      // If new user, also store createdAt
      userData['createdAt'] = FieldValue.serverTimestamp();
    }

    await docRef.set(userData, SetOptions(merge: true));
    print('Profile data saved successfully'); // Debug log
  }

  /// 🔒 Check if email already exists for a different user
  Future<bool> isEmailTaken(String email, String currentUserId) async {
    try {
      final emailQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .get();

      for (final doc in emailQuery.docs) {
        // Email is taken if it belongs to a different user
        if (doc.id != currentUserId) {
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error checking email: $e');
      return false;
    }
  }

  /// 🔒 Check if phone number already exists for a different user
  Future<bool> isPhoneTaken(String phone, String currentUserId) async {
    try {
      // Normalize phone number (remove spaces, ensure +91 prefix)
      String normalizedPhone = phone.replaceAll(' ', '').replaceAll('-', '');
      if (!normalizedPhone.startsWith('+')) {
        normalizedPhone = '+91$normalizedPhone';
      }
      
      final phoneQuery = await _firestore
          .collection('users')
          .where('phone', isEqualTo: normalizedPhone)
          .get();

      for (final doc in phoneQuery.docs) {
        // Phone is taken if it belongs to a different user
        if (doc.id != currentUserId) {
          return true;
        }
      }
      
      // Also check without country code
      final phoneWithoutCode = normalizedPhone.replaceFirst('+91', '');
      final phoneQuery2 = await _firestore
          .collection('users')
          .where('phone', isEqualTo: phoneWithoutCode)
          .get();

      for (final doc in phoneQuery2.docs) {
        if (doc.id != currentUserId) {
          return true;
        }
      }
      
      return false;
    } catch (e) {
      print('Error checking phone: $e');
      return false;
    }
  }

  /// 📱 Update user phone number (after OTP verification)
  Future<void> updateUserPhone(String userId, String phone) async {
    await _firestore.collection('users').doc(userId).update({
      'phone': phone,
      'phoneVerified': true,
      'phoneVerifiedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    print('Phone number updated for user: $userId');
  }

  /// 📧 Update user email (after verification)
  Future<void> updateUserEmail(String userId, String email) async {
    await _firestore.collection('users').doc(userId).update({
      'email': email.toLowerCase(),
      'emailVerified': true,
      'emailVerifiedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    print('Email updated for user: $userId');
  }

  /// Fetch user details (optional utility)
  Future<Map<String, dynamic>?> getUserDetails(String uid) async {
    print('Firestore: Fetching user details for UID: $uid'); // Debug log
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      print('Firestore: Document exists: ${doc.exists}'); // Debug log
      if (doc.exists) {
        final data = doc.data();
        print('Firestore: Document data: $data'); // Debug log
        return data;
      } else {
        print('Firestore: No document found for UID: $uid'); // Debug log
        return null;
      }
    } catch (e) {
      print('Firestore: Error fetching user details: $e'); // Debug log
      return null;
    }
  }

  // Follow a user
  Future<void> followUser(String currentUserId, String userIdToFollow) async {
    // Add to current user's following list
    await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('following')
        .doc(userIdToFollow)
        .set({'timestamp': FieldValue.serverTimestamp()});

    // Add to the other user's followers list
    await _firestore
        .collection('users')
        .doc(userIdToFollow)
        .collection('followers')
        .doc(currentUserId)
        .set({'timestamp': FieldValue.serverTimestamp()});
  }

  // Unfollow a user
  Future<void> unfollowUser(
    String currentUserId,
    String userIdToUnfollow,
  ) async {
    // Remove from current user's following list
    await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('following')
        .doc(userIdToUnfollow)
        .delete();

    // Remove from the other user's followers list
    await _firestore
        .collection('users')
        .doc(userIdToUnfollow)
        .collection('followers')
        .doc(currentUserId)
        .delete();
  }

  // Check if a user is following another
  Future<bool> isFollowing(String currentUserId, String userIdToCheck) async {
    final doc =
        await _firestore
            .collection('users')
            .doc(currentUserId)
            .collection('following')
            .doc(userIdToCheck)
            .get();
    return doc.exists;
  }

  // Get following count
  Future<int> getFollowingCount(String userId) async {
    final snapshot =
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('following')
            .get();
    return snapshot.size;
  }

  // Get followers count
  Future<int> getFollowersCount(String userId) async {
    final snapshot =
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('followers')
            .get();
    return snapshot.size;
  }
}

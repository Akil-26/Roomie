import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:roomie/data/datasources/cloudinary_service.dart';

/// New profile image service using Cloudinary.
/// Legacy MongoDB logic removed. All calls now return a Cloudinary URL.
class ProfileImageService {
  final _cloudinary = CloudinaryService();

  /// Test Cloudinary connection configuration
  void testCloudinaryConnection() {
    _cloudinary.testConnection();
  }

  /// Upload and return secure URL. Handles both mobile File and web XFile.
  Future<String?> saveUserProfileImage({
    required String userId,
    required dynamic imageFile, // Can be File or XFile
    String? previousImageId, // kept for backward compatibility; unused now
  }) async {
    try {
      if (kIsWeb && imageFile is XFile) {
        // Web: Use XFile.readAsBytes()
        debugPrint('Web upload: Using XFile.readAsBytes()');
        final bytes = await imageFile.readAsBytes();
        final url = await _cloudinary.uploadBytes(
          bytes: bytes,
          fileName: imageFile.name,
          folder: CloudinaryFolder.profile,
          publicId: 'profile_$userId',
          context: {'userId': userId, 'type': 'profile'},
        );
        if (url == null) {
          debugPrint('Cloudinary: failed to upload profile image');
        }
        return url;
      } else if (!kIsWeb && imageFile is File) {
        // Mobile: Use File
        debugPrint('Mobile upload: Using File');
        final url = await _cloudinary.uploadFile(
          file: imageFile,
          folder: CloudinaryFolder.profile,
          publicId: 'profile_$userId',
          context: {'userId': userId, 'type': 'profile'},
        );
        if (url == null) {
          debugPrint('Cloudinary: failed to upload profile image');
        }
        return url;
      } else {
        debugPrint('Unsupported image file type: ${imageFile.runtimeType}');
        return null;
      }
    } catch (e) {
      debugPrint('Cloudinary: failed to upload profile image: $e');
      return null;
    }
  }

  /// Backward compatibility: previously returned Base64 by imageId. Now we expect a full URL already stored.
  Future<String?> getUserProfileImage(String imageUrlOrLegacyId) async {
    // If the stored value already looks like a URL, return it directly.
    if (imageUrlOrLegacyId.startsWith('http')) return imageUrlOrLegacyId;
    // Legacy path unsupported now.
    print(
      'Legacy MongoDB imageId encountered: $imageUrlOrLegacyId (no lookup)',
    );
    return null;
  }

  // Legacy no-ops kept to avoid breaking old references.
  Future<List<Map<String, dynamic>>> getUserProfileImageHistory(
    String userId,
  ) async => [];
  Future<bool> setActiveProfileImage(String userId, String imageId) async =>
      true;
  Future<bool> deleteProfileImage(String imageId, String userId) async => true;
  Future<void> cleanupOldProfileImages(String userId) async {}
  Future<Map<String, dynamic>?> getProfileImageMetadata(String imageId) async =>
      null;
}

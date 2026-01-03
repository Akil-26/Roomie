import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

/// Cached user data model
class CachedUser {
  final String id;
  final String displayName;
  final String? profileImageUrl;
  final String? email;
  final DateTime cachedAt;

  CachedUser({
    required this.id,
    required this.displayName,
    this.profileImageUrl,
    this.email,
    DateTime? cachedAt,
  }) : cachedAt = cachedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'profileImageUrl': profileImageUrl,
      'email': email,
      'cachedAt': cachedAt.toIso8601String(),
    };
  }

  factory CachedUser.fromMap(Map<String, dynamic> map) {
    return CachedUser(
      id: map['id'] as String,
      displayName: map['displayName'] as String? ?? 'User',
      profileImageUrl: map['profileImageUrl'] as String?,
      email: map['email'] as String?,
      cachedAt: map['cachedAt'] != null
          ? DateTime.parse(map['cachedAt'] as String)
          : DateTime.now(),
    );
  }
}

/// Service to cache user data locally using Hive for faster loading
class UserCacheService {
  static final UserCacheService _instance = UserCacheService._internal();
  factory UserCacheService() => _instance;
  UserCacheService._internal();

  static const String _boxName = 'user_cache';
  Box<Map>? _box;
  bool _initialized = false;

  /// Initialize the Hive box for user caching
  Future<void> init() async {
    if (_initialized) return;

    try {
      _box = await Hive.openBox<Map>(_boxName);
      _initialized = true;
      debugPrint('✅ User cache service initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize user cache: $e');
    }
  }

  /// Cache a single user
  Future<void> cacheUser(CachedUser user) async {
    if (_box == null) return;

    try {
      await _box!.put(user.id, user.toMap());
    } catch (e) {
      debugPrint('❌ Failed to cache user ${user.id}: $e');
    }
  }

  /// Cache multiple users at once
  Future<void> cacheUsers(List<CachedUser> users) async {
    if (_box == null || users.isEmpty) return;

    try {
      final Map<String, Map<String, dynamic>> entries = {};
      for (final user in users) {
        entries[user.id] = user.toMap();
      }
      await _box!.putAll(entries);
    } catch (e) {
      debugPrint('❌ Failed to cache users: $e');
    }
  }

  /// Get a cached user by ID
  CachedUser? getCachedUser(String userId) {
    if (_box == null) return null;

    try {
      final data = _box!.get(userId);
      if (data != null) {
        return CachedUser.fromMap(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      debugPrint('❌ Failed to get cached user $userId: $e');
    }
    return null;
  }

  /// Get multiple cached users by IDs
  Map<String, CachedUser> getCachedUsers(List<String> userIds) {
    if (_box == null) return {};

    final Map<String, CachedUser> result = {};
    for (final userId in userIds) {
      final user = getCachedUser(userId);
      if (user != null) {
        result[userId] = user;
      }
    }
    return result;
  }

  /// Check if a user is cached
  bool isUserCached(String userId) {
    if (_box == null) return false;
    return _box!.containsKey(userId);
  }

  /// Check if user cache is stale (older than specified duration)
  bool isUserStale(String userId, {Duration maxAge = const Duration(hours: 24)}) {
    final user = getCachedUser(userId);
    if (user == null) return true;
    
    final now = DateTime.now();
    return now.difference(user.cachedAt) > maxAge;
  }

  /// Update user's profile image URL
  Future<void> updateUserImage(String userId, String? imageUrl) async {
    final user = getCachedUser(userId);
    if (user == null) return;

    await cacheUser(CachedUser(
      id: user.id,
      displayName: user.displayName,
      profileImageUrl: imageUrl,
      email: user.email,
    ));
  }

  /// Update user's display name
  Future<void> updateUserName(String userId, String displayName) async {
    final user = getCachedUser(userId);
    if (user == null) {
      await cacheUser(CachedUser(id: userId, displayName: displayName));
      return;
    }

    await cacheUser(CachedUser(
      id: user.id,
      displayName: displayName,
      profileImageUrl: user.profileImageUrl,
      email: user.email,
    ));
  }

  /// Delete a cached user
  Future<void> deleteUser(String userId) async {
    if (_box == null) return;

    try {
      await _box!.delete(userId);
    } catch (e) {
      debugPrint('❌ Failed to delete cached user $userId: $e');
    }
  }

  /// Clear all cached users
  Future<void> clearAll() async {
    if (_box == null) return;

    try {
      await _box!.clear();
      debugPrint('🗑️ User cache cleared');
    } catch (e) {
      debugPrint('❌ Failed to clear user cache: $e');
    }
  }

  /// Get all cached users (for debugging)
  List<CachedUser> getAllCachedUsers() {
    if (_box == null) return [];

    try {
      return _box!.values
          .map((data) => CachedUser.fromMap(Map<String, dynamic>.from(data)))
          .toList();
    } catch (e) {
      debugPrint('❌ Failed to get all cached users: $e');
      return [];
    }
  }
}

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:roomie/data/datasources/cloudinary_service.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:roomie/data/datasources/notification_service.dart';
import 'package:roomie/data/models/room_member_model.dart';
import 'package:roomie/data/models/room_ownership_request_model.dart';
import 'package:roomie/data/models/room_join_request_model.dart';

/// Singleton service for group operations with caching
/// 
/// IMPORTANT RULES FOR ROOM PERSISTENCE:
/// 1. Rooms should NEVER be auto-deleted when users leave
/// 2. Only change status to 'inactive' instead of deleting
/// 3. Leaving users should not affect room visibility
/// 4. Room existence is independent of member count
/// 
/// STEP-2: OWNER CLAIM RULES:
/// 5. Owner can request to manage an existing room (not create duplicate)
/// 6. On approval: set room.ownerId, change creationType to 'owner_created'
/// 7. Room ID NEVER changes during ownership claim
/// 8. Existing roommates are NOT affected by ownership claim
class GroupsService {
  // Singleton pattern
  static final GroupsService _instance = GroupsService._internal();
  factory GroupsService() => _instance;
  GroupsService._internal();

  final _firestore = FirebaseFirestore.instance;
  final _realtimeDB = FirebaseDatabase.instance;
  final _cloudinary = CloudinaryService();
  final _notificationService = NotificationService();
  static const String _collection = 'groups';
  static const String _roomMembersCollection = 'room_members';
  static const String _ownershipRequestsCollection = 'room_ownership_requests';
  static const String _joinRequestsCollection = 'room_join_requests';

  // Cache for current user's group (user-specific)
  Map<String, dynamic>? _currentGroupCache;
  DateTime? _currentGroupCacheTime;
  String? _cachedUserId; // Track which user the cache belongs to
  static const Duration _cacheExpiry = Duration(minutes: 2);

  /// Clear cache (call on logout, account switch, or group change)
  void clearCache() {
    _currentGroupCache = null;
    _currentGroupCacheTime = null;
    _cachedUserId = null;
    print('GroupsService: Cache cleared');
  }

  Future<String?> createGroup({
    required String name,
    required String description,
    required String location,
    double? lat,
    double? lng,
    required int memberCount,
    required int maxMembers,
    required double rentAmount,
    required String rentCurrency,
    required double advanceAmount,
    required String roomType,
    required List<String> amenities,
    List<File> imageFiles = const [],
    List<XFile> webPickedFiles = const [],
    File? imageFile,
    XFile? webPicked,
  }) async {
    final user = AuthService().currentUser;
    if (user == null) throw Exception('Not authenticated');

    final canCreate = await canUserCreateGroup();
    if (!canCreate) {
      throw Exception('You can only create or join one group at a time');
    }

    final docRef = _firestore.collection(_collection).doc();
    final List<String> imageUrls = [];

    final List<File> allLocalImages = [
      ...imageFiles,
      if (imageFile != null) imageFile,
    ];

    final List<XFile> allWebImages = [
      ...webPickedFiles,
      if (webPicked != null) webPicked,
    ];

    if (!kIsWeb && allLocalImages.isNotEmpty) {
      for (var index = 0; index < allLocalImages.length; index++) {
        final file = allLocalImages[index];
        final url = await _cloudinary.uploadFile(
          file: file,
          folder: CloudinaryFolder.groups,
          publicId: 'group_${docRef.id}_${index + 1}',
          context: {'groupId': docRef.id, 'createdBy': user.uid},
        );
        if (url != null) {
          imageUrls.add(url);
        }
      }
    } else if (kIsWeb && allWebImages.isNotEmpty) {
      for (var index = 0; index < allWebImages.length; index++) {
        final image = allWebImages[index];
        final bytes = await image.readAsBytes();
        final url = await _cloudinary.uploadBytes(
          bytes: bytes,
          fileName: image.name,
          folder: CloudinaryFolder.groups,
          publicId: 'group_${docRef.id}_${index + 1}',
          context: {'groupId': docRef.id, 'createdBy': user.uid},
        );
        if (url != null) {
          imageUrls.add(url);
        }
      }
    }

    final rentDetails = {
      'amount': rentAmount,
      'currency': rentCurrency,
      'advanceAmount': advanceAmount,
    };

    final data = {
      'id': docRef.id,
      'name': name.trim(),
      'description': description.trim(),
      'location': location.trim(),
      'lat': lat,
      'lng': lng,
      'memberCount': memberCount,
      'maxMembers': maxMembers,
      'rent': rentDetails,
      'rentAmount': rentAmount,
      'rentCurrency': rentCurrency,
      'advanceAmount': advanceAmount,
      'roomType': roomType,
      'amenities': amenities,
      'imageUrl': imageUrls.isNotEmpty ? imageUrls.first : null,
      'images': imageUrls,
      'imageCount': imageUrls.length,
      'createdBy': user.uid,
      'members': [user.uid],
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      // === NEW FIELDS FOR ROOM PERSISTENCE ===
      'status': 'active', // Room status: active | inactive (NEVER delete rooms)
      'isPublic': true, // Whether room appears in available rooms
      'creationType': 'user_created', // user_created | owner_created
      'ownerId': null, // For future owner-merge feature
    };

    await docRef.set(data);
    
    // Create room member record for the creator
    await _createRoomMemberRecord(
      roomId: docRef.id,
      userId: user.uid,
      role: 'admin',
    );
    
    await _updateGroupChatMembers(docRef.id);

    // Invalidate cache after creating group
    clearCache();

    print('Group created successfully: ${docRef.id} for user: ${user.uid}');
    print('Group data: $data');
    return docRef.id;
  }

  Future<List<Map<String, dynamic>>> getAllGroups() async {
    final snapshot =
        await _firestore
            .collection(_collection)
            .where('isActive', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .get();
    return snapshot.docs.map((d) => d.data()).toList();
  }

  // Get current user's group (created or joined) with caching
  Future<Map<String, dynamic>?> getCurrentUserGroup({bool forceRefresh = false}) async {
    final user = AuthService().currentUser;
    if (user == null) {
      print('No user authenticated for getCurrentUserGroup');
      clearCache(); // Clear any stale cache when no user
      return null;
    }

    // Invalidate cache if user changed (account switch)
    if (_cachedUserId != null && _cachedUserId != user.uid) {
      print('User changed from $_cachedUserId to ${user.uid}, clearing cache');
      clearCache();
    }

    // Return cached data if valid and not forcing refresh
    if (!forceRefresh && 
        _currentGroupCache != null && 
        _currentGroupCacheTime != null &&
        _cachedUserId == user.uid &&
        DateTime.now().difference(_currentGroupCacheTime!) < _cacheExpiry) {
      print('Returning cached current group');
      return _currentGroupCache;
    }

    print('Getting current group for user: ${user.uid}');

    final snapshot =
        await _firestore
            .collection(_collection)
            .where('isActive', isEqualTo: true)
            .where('members', arrayContains: user.uid)
            .limit(1)
            .get();

    print('Found ${snapshot.docs.length} groups for current user');

    if (snapshot.docs.isNotEmpty) {
      final groupData = snapshot.docs.first.data();
      // Update cache with user ID
      _currentGroupCache = groupData;
      _currentGroupCacheTime = DateTime.now();
      _cachedUserId = user.uid;
      print('Current user group: ${groupData['name']} (${groupData['id']})');
      return groupData;
    }

    // Cache the null result too (with user ID)
    _currentGroupCache = null;
    _currentGroupCacheTime = DateTime.now();
    _cachedUserId = user.uid;
    print('No current group found for user');
    return null;
  }

  // Check if user can create a new group (hasn't created or joined any)
  Future<bool> canUserCreateGroup() async {
    final currentGroup = await getCurrentUserGroup();
    return currentGroup == null;
  }

  // Get available groups (excluding user's current group)
  // UPDATED: Rooms shown based on status == 'active' AND isPublic == true
  // This ensures rooms remain visible even if all members leave
  Future<List<Map<String, dynamic>>> getAvailableGroups() async {
    final user = AuthService().currentUser;
    if (user == null) {
      print('No user authenticated for getAvailableGroups');
      return [];
    }

    print('Getting available groups for user: ${user.uid}');

    // Query rooms that are:
    // 1. status == 'active' (not deactivated)
    // 2. isPublic == true (visible in listings)
    // Note: We check both 'isActive' (legacy) and 'status' for backward compatibility
    final snapshot =
        await _firestore
            .collection(_collection)
            .where('isActive', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .get();

    print('Total groups found: ${snapshot.docs.length}');

    final availableGroups =
        snapshot.docs.map((d) => d.data()).where((group) {
          final members = List<String>.from(group['members'] ?? []);
          final isUserMember = members.contains(user.uid);
          // Check room status and visibility
          final status = group['status'] ?? 'active';
          final isPublic = group['isPublic'] ?? true;
          final isRoomAvailable = status == 'active' && isPublic;
          
          print(
            'Group ${group['name']}: members=$members, userIsMember=$isUserMember, status=$status, isPublic=$isPublic',
          );
          // Room is available if: active, public, and user is not already a member
          return isRoomAvailable && !isUserMember;
        }).toList();

    print('Available groups count: ${availableGroups.length}');
    return availableGroups;
  }

  Future<bool> joinGroup(String groupId) async {
    final user = AuthService().currentUser;
    if (user == null) return false;

    final groupDoc = _firestore.collection(_collection).doc(groupId);
    final groupSnapshot = await groupDoc.get();

    if (!groupSnapshot.exists) {
      throw Exception('Group not found');
    }

    final groupData = groupSnapshot.data()!;
    final members = List<String>.from(groupData['members'] ?? []);
    final maxMembers = groupData['maxMembers'] as int;
    
    // Check room status before allowing join
    final status = groupData['status'] ?? 'active';
    if (status != 'active') {
      throw Exception('This room is no longer available');
    }

    if (members.length >= maxMembers) {
      throw Exception('Group is already full');
    }

    if (members.contains(user.uid)) {
      throw Exception('You are already in this group');
    }

    await groupDoc.update({
      'members': FieldValue.arrayUnion([user.uid]),
      'memberCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Create or reactivate room member record
    await _createOrReactivateRoomMember(
      roomId: groupId,
      userId: user.uid,
      role: 'member',
    );

    await _updateGroupChatMembers(groupId);
    
    // Invalidate cache
    clearCache();
    
    return true;
  }

  Future<void> switchGroup({
    required String userId,
    required String currentGroupId,
    required String newGroupId,
  }) async {
    final user = AuthService().currentUser;
    if (user == null || user.uid != userId) {
      throw Exception('Authentication error.');
    }

    final currentGroupRef = _firestore
        .collection(_collection)
        .doc(currentGroupId);
    final newGroupRef = _firestore.collection(_collection).doc(newGroupId);

    await _firestore.runTransaction((transaction) async {
      // Get both group documents
      final currentGroupSnap = await transaction.get(currentGroupRef);
      final newGroupSnap = await transaction.get(newGroupRef);

      if (!currentGroupSnap.exists) {
        throw Exception('Your current group could not be found.');
      }
      if (!newGroupSnap.exists) {
        throw Exception('The new group could not be found.');
      }

      // Leave the current group
      transaction.update(currentGroupRef, {
        'members': FieldValue.arrayRemove([userId]),
        'memberCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Join the new group
      transaction.update(newGroupRef, {
        'members': FieldValue.arrayUnion([userId]),
        'memberCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    // Update real-time chat members for both groups
    await _updateGroupChatMembers(currentGroupId);
    await _updateGroupChatMembers(newGroupId);
    
    // Update room member records
    await _markRoomMemberAsLeft(currentGroupId, userId);
    await _createOrReactivateRoomMember(
      roomId: newGroupId,
      userId: userId,
      role: 'member',
    );
    
    // Invalidate cache
    clearCache();
  }

  /// Leave a group - CRITICAL: This will NEVER delete the room
  /// 
  /// When a user leaves:
  /// 1. Remove user from members array
  /// 2. Decrement member count
  /// 3. Mark room_member record as inactive (isActive = false, leftAt = timestamp)
  /// 4. Room remains visible in available rooms (if status == 'active' && isPublic == true)
  Future<void> leaveGroup(String groupId) async {
    final user = AuthService().currentUser;
    if (user == null) throw Exception('Not authenticated');

    final ref = _firestore.collection(_collection).doc(groupId);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Group does not exist');

      final data = snap.data()!;
      final members = List<String>.from(data['members'] ?? []);

      if (members.contains(user.uid)) {
        members.remove(user.uid);

        // IMPORTANT: NEVER delete the room, even if empty
        // Just update the member list - room persists independently
        tx.update(ref, {
          'members': members,
          'memberCount': members.length,
          'currentMembers': members.length,
          'updatedAt': FieldValue.serverTimestamp(),
          // Room status remains 'active' - it's still available for others to join
        });
        
        print('✅ User ${user.uid} left group $groupId. Remaining members: ${members.length}');
        print('📌 Room persists - NOT deleted. Room is still available for others.');
      } else {
        throw Exception('User is not a member of this group');
      }
    });

    // Mark the room member record as inactive (DO NOT delete)
    await _markRoomMemberAsLeft(groupId, user.uid);
    
    // Update real-time chat members
    await _updateGroupChatMembers(groupId);
    
    // Invalidate cache
    clearCache();
    
    print('✅ Leave group completed. Room $groupId remains active.');
  }

  // ============================================================
  // ROOM MEMBER MANAGEMENT METHODS
  // These methods manage the room_members collection for tracking
  // user-room relationships independently of the room itself
  // ============================================================

  /// Create a new room member record
  Future<void> _createRoomMemberRecord({
    required String roomId,
    required String userId,
    required String role,
  }) async {
    try {
      final memberRef = _firestore.collection(_roomMembersCollection).doc();
      final memberData = RoomMemberModel(
        id: memberRef.id,
        roomId: roomId,
        userId: userId,
        role: role,
        joinedAt: DateTime.now(),
        isActive: true,
      );
      
      await memberRef.set(memberData.toMap());
      print('✅ Created room member record: ${memberRef.id} for user $userId in room $roomId');
    } catch (e) {
      print('❌ Error creating room member record: $e');
      // Don't throw - this is a secondary operation
    }
  }

  /// Create or reactivate a room member record
  /// If user previously left this room, reactivate the record instead of creating new
  Future<void> _createOrReactivateRoomMember({
    required String roomId,
    required String userId,
    required String role,
  }) async {
    try {
      // Check if user has an existing (inactive) record for this room
      final existingQuery = await _firestore
          .collection(_roomMembersCollection)
          .where('roomId', isEqualTo: roomId)
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      if (existingQuery.docs.isNotEmpty) {
        // Reactivate existing record
        final existingDoc = existingQuery.docs.first;
        await existingDoc.reference.update({
          'isActive': true,
          'leftAt': null,
          'joinedAt': FieldValue.serverTimestamp(),
          'role': role,
        });
        print('✅ Reactivated room member record for user $userId in room $roomId');
      } else {
        // Create new record
        await _createRoomMemberRecord(
          roomId: roomId,
          userId: userId,
          role: role,
        );
      }
    } catch (e) {
      print('❌ Error in _createOrReactivateRoomMember: $e');
    }
  }

  /// Mark a room member as having left (DO NOT delete the record)
  Future<void> _markRoomMemberAsLeft(String roomId, String userId) async {
    try {
      final query = await _firestore
          .collection(_roomMembersCollection)
          .where('roomId', isEqualTo: roomId)
          .where('userId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        await query.docs.first.reference.update({
          'isActive': false,
          'leftAt': FieldValue.serverTimestamp(),
        });
        print('✅ Marked room member as left: user $userId from room $roomId');
      }
    } catch (e) {
      print('❌ Error marking room member as left: $e');
    }
  }

  /// Get active members of a room from room_members collection
  Future<List<RoomMemberModel>> getRoomMembers(String roomId) async {
    try {
      final query = await _firestore
          .collection(_roomMembersCollection)
          .where('roomId', isEqualTo: roomId)
          .where('isActive', isEqualTo: true)
          .get();

      return query.docs
          .map((doc) => RoomMemberModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ Error getting room members: $e');
      return [];
    }
  }

  /// Get room membership history (including past members)
  Future<List<RoomMemberModel>> getRoomMembershipHistory(String roomId) async {
    try {
      final query = await _firestore
          .collection(_roomMembersCollection)
          .where('roomId', isEqualTo: roomId)
          .orderBy('joinedAt', descending: true)
          .get();

      return query.docs
          .map((doc) => RoomMemberModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ Error getting room membership history: $e');
      return [];
    }
  }

  /// Check if user is an active member of a room
  Future<bool> isUserActiveMember(String roomId, String userId) async {
    try {
      final query = await _firestore
          .collection(_roomMembersCollection)
          .where('roomId', isEqualTo: roomId)
          .where('userId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      print('❌ Error checking active membership: $e');
      return false;
    }
  }

  // ============================================================
  // END ROOM MEMBER MANAGEMENT METHODS
  // ============================================================

  Future<bool> updateGroup({
    required String groupId,
    String? name,
    String? description,
    String? location,
    double? rentAmount,
    String? rentCurrency,
    double? advanceAmount,
    File? newImageFile,
  }) async {
    final ref = _firestore.collection(_collection).doc(groupId);
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) updates['name'] = name.trim();
    if (description != null) updates['description'] = description.trim();
    if (location != null) updates['location'] = location.trim();
    final rentUpdates = <String, dynamic>{};
    if (rentAmount != null) {
      rentUpdates['amount'] = rentAmount;
      updates['rentAmount'] = rentAmount;
    }
    if (rentCurrency != null) {
      rentUpdates['currency'] = rentCurrency;
      updates['rentCurrency'] = rentCurrency;
    }
    if (advanceAmount != null) {
      rentUpdates['advanceAmount'] = advanceAmount;
      updates['advanceAmount'] = advanceAmount;
    }

    if (rentUpdates.isNotEmpty) {
      final currentSnapshot = await ref.get();
      final currentRent = Map<String, dynamic>.from(
        (currentSnapshot.data()?['rent'] as Map<String, dynamic>?) ?? {},
      );
      final mergedRent = {...currentRent, ...rentUpdates};
      updates['rent'] = mergedRent;
    }

    if (newImageFile != null) {
      final url = await _cloudinary.uploadFile(
        file: newImageFile,
        folder: CloudinaryFolder.groups,
        publicId: 'group_$groupId',
        context: {'groupId': groupId},
      );
      if (url != null) updates['imageUrl'] = url;
    }
    await ref.update(updates);
    return true;
  }

  /// Deactivate a room (soft delete)
  /// IMPORTANT: This does NOT delete the room, just changes its status to 'inactive'
  /// The room data is preserved for history and potential reactivation
  Future<bool> deleteGroup(String groupId) async {
    final ref = _firestore.collection(_collection).doc(groupId);
    await ref.update({
      'isActive': false,
      'status': 'inactive', // New field for room persistence
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    print('✅ Room $groupId deactivated (soft deleted). Data preserved.');
    return true;
  }

  /// Reactivate a previously deactivated room
  Future<bool> reactivateRoom(String groupId) async {
    final ref = _firestore.collection(_collection).doc(groupId);
    await ref.update({
      'isActive': true,
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    print('✅ Room $groupId reactivated.');
    return true;
  }

  /// Set room visibility (public/private)
  Future<bool> setRoomVisibility(String groupId, bool isPublic) async {
    final ref = _firestore.collection(_collection).doc(groupId);
    await ref.update({
      'isPublic': isPublic,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    print('✅ Room $groupId visibility set to ${isPublic ? 'public' : 'private'}');
    return true;
  }

  // 🔔 Send join request to group
  Future<bool> sendJoinRequest(String groupId) async {
    final user = AuthService().currentUser;
    if (user == null) return false;

    try {
      // Get user details
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};

      // Create join request
      final requestRef = _firestore.collection('joinRequests').doc();
      await requestRef.set({
        'id': requestRef.id,
        'groupId': groupId,
        'userId': user.uid,
        'userName': userData['username'] ?? userData['name'] ?? 'Unknown User',
        'userEmail': userData['email'] ?? user.email ?? '',
        'userPhone': userData['phone'] ?? '',
        'userAge': userData['age'],
        'userOccupation': userData['occupation'],
        'userProfileImage': userData['profileImageUrl'],
        'status': 'pending', // pending, approved, rejected
        'requestedAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
      });

      // Notify all group members about the new request
      final groupDocForNotify =
          await _firestore.collection(_collection).doc(groupId).get();
      final groupDataForNotify = groupDocForNotify.data();
      if (groupDataForNotify != null) {
        final groupMembers = List<String>.from(
          groupDataForNotify['members'] ?? [],
        );
        final groupName = groupDataForNotify['name'] ?? 'your group';
        for (final memberId in groupMembers) {
          // Don't notify the user who sent the request
          if (memberId == user.uid) continue;

          await _notificationService.sendUserNotification(
            userId: memberId,
            title: 'New Join Request',
            body:
                '${userData['username'] ?? userData['name'] ?? 'Someone'} requested to join "$groupName".',
            type: 'join_request_received',
            data: {
              'groupId': groupId,
              'requestId': requestRef.id,
              'requesterId': user.uid,
            },
          );
        }
      }

      print('✅ Join request sent for group: $groupId');
      return true;
    } catch (e) {
      print('❌ Error sending join request: $e');
      return false;
    }
  }

  // 🔍 Get join requests for a group (for group members to review)
  Stream<List<Map<String, dynamic>>> getGroupJoinRequests(String groupId) {
    return _firestore
        .collection('joinRequests')
        .where('groupId', isEqualTo: groupId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          // Sort in memory instead of using orderBy
          final docs =
              snapshot.docs.map((doc) {
                final data = doc.data();
                data['id'] = doc.id;
                return data;
              }).toList();

          // Sort by requestedAt in descending order
          docs.sort((a, b) {
            final aTime = a['requestedAt'];
            final bTime = b['requestedAt'];
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });

          return docs;
        });
  }

  // ✅ Approve join request
  Future<bool> approveJoinRequest(
    String requestId,
    String groupId,
    String userId,
  ) async {
    final currentUser = AuthService().currentUser;
    if (currentUser == null) return false;

    try {
      // Get the group and request documents
      final requestRef = _firestore.collection('joinRequests').doc(requestId);
      final groupRef = _firestore.collection(_collection).doc(groupId);

      final requestSnap = await requestRef.get();
      if (!requestSnap.exists) throw Exception('Join request not found');

      final groupSnap = await groupRef.get();
      if (!groupSnap.exists) throw Exception('Group not found');

      final groupData = groupSnap.data()!;
      final members = List<String>.from(groupData['members'] ?? []);

      // Check if current user is a member of this group (can approve)
      if (!members.contains(currentUser.uid)) {
        throw Exception('You are not authorized to approve this request');
      }

      // Check if the requesting user is already in a group
      final requestingUserGroup = await _getUserGroup(userId);
      if (requestingUserGroup != null) {
        // User is already in a group, send a conflict notification
        await _notificationService.sendUserNotification(
          userId: userId,
          title: 'Your request for ${groupData['name']} was approved!',
          body: 'You are already in another group. Would you like to switch?',
          type: 'group_join_conflict',
          data: {
            'newGroupId': groupId,
            'currentGroupId': requestingUserGroup['id'],
          },
        );
      } else {
        // User is not in a group, add them directly
        await _firestore.runTransaction((tx) async {
          if (!members.contains(userId)) {
            members.add(userId);
            tx.update(groupRef, {
              'members': members,
              'memberCount': members.length,
              'currentMembers': members.length,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        });
        
        // Create room member record for the new member
        await _createOrReactivateRoomMember(
          roomId: groupId,
          userId: userId,
          role: 'member',
        );
        
        await _updateGroupChatMembers(groupId);
      }

      // Update request status regardless
      await requestRef.update({
        'status': 'approved',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': currentUser.uid,
      });

      await _notificationService.clearJoinRequestNotifications(
        requestId: requestId,
        memberIds: members,
      );
      
      // Invalidate cache
      clearCache();

      return true;
    } catch (e) {
      print('❌ Error approving join request: $e');
      return false;
    }
  }

  // Helper to get a specific user's group
  Future<Map<String, dynamic>?> _getUserGroup(String userId) async {
    final snapshot =
        await _firestore
            .collection(_collection)
            .where('isActive', isEqualTo: true)
            .where('members', arrayContains: userId)
            .limit(1)
            .get();

    if (snapshot.docs.isNotEmpty) {
      return snapshot.docs.first.data();
    }
    return null;
  }

  Future<Map<String, dynamic>?> getGroupById(String groupId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(groupId).get();
      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      return {...data, 'id': data['id'] ?? doc.id};
    } catch (e) {
      print('❌ Error fetching group by ID: $e');
      return null;
    }
  }

  // Update group chat members in Realtime Database
  Future<void> _updateGroupChatMembers(String groupId) async {
    try {
      // Get updated group data from Firestore
      final groupDoc =
          await _firestore.collection(_collection).doc(groupId).get();
      if (!groupDoc.exists) return;

      final groupData = groupDoc.data()!;
      final members = List<String>.from(groupData['members'] ?? []);
      final groupName = groupData['name'] ?? 'Group Chat';

      // Update group chat in Realtime Database
      final chatRef = _realtimeDB.ref('groupChats/$groupId');
      final chatSnapshot = await chatRef.get();

      if (chatSnapshot.exists) {
        // Update existing group chat
        await chatRef.update({
          'members': members,
          'memberNames': {
            for (String memberId in members) memberId: 'Member',
          }, // You can enhance this
        });
        print('✅ Updated group chat members for group: $groupId');
      } else {
        // Create new group chat if it doesn't exist
        final chatData = {
          'id': groupId,
          'groupName': groupName,
          'members': members,
          'memberNames': {for (String memberId in members) memberId: 'Member'},
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'lastMessage': 'Group created',
          'lastSenderId': 'system',
          'lastMessageTime': DateTime.now().millisecondsSinceEpoch,
          'unreadCounts': {for (String memberId in members) memberId: 0},
        };

        await chatRef.set(chatData);
        print('✅ Created new group chat for group: $groupId');
      }
    } catch (e) {
      print('❌ Error updating group chat members: $e');
    }
  }

  // ❌ Reject join request
  Future<bool> rejectJoinRequest(String requestId, String groupId) async {
    final currentUser = AuthService().currentUser;
    if (currentUser == null) return false;

    try {
      final requestRef = _firestore.collection('joinRequests').doc(requestId);

      // Get member IDs from the group to clear their notifications
      final groupSnap =
          await _firestore.collection(_collection).doc(groupId).get();
      final memberIds = List<String>.from(groupSnap.data()?['members'] ?? []);

      // Update the request status
      await requestRef.update({
        'status': 'rejected',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': currentUser.uid,
      });

      // Clear notifications for all members
      if (memberIds.isNotEmpty) {
        await _notificationService.clearJoinRequestNotifications(
          requestId: requestId,
          memberIds: memberIds,
        );
      }

      print('✅ Join request rejected: $requestId');
      return true;
    } catch (e) {
      print('❌ Error rejecting join request: $e');
      return false;
    }
  }

  // 📋 Get user's pending join requests
  Stream<List<Map<String, dynamic>>> getUserJoinRequests(String userId) {
    return _firestore
        .collection('joinRequests')
        .where('userId', isEqualTo: userId)
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
        });
  }

  // 🔍 Check if user has pending request for a group
  Future<bool> hasPendingRequest(String groupId, String userId) async {
    try {
      final query =
          await _firestore
              .collection('joinRequests')
              .where('groupId', isEqualTo: groupId)
              .where('userId', isEqualTo: userId)
              .where('status', isEqualTo: 'pending')
              .limit(1)
              .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      print('❌ Error checking pending request: $e');
      return false;
    }
  }

  // ============================================================
  // STEP-2: OWNER CLAIM & MANAGEMENT
  // ============================================================
  // RULES:
  // - Owner can request to manage existing room (no duplication)
  // - On approval: room.ownerId is set, creationType becomes 'owner_created'
  // - Room ID NEVER changes
  // - Existing roommates are NOT affected
  // - Owner is NOT added as roommate (separate role)
  // ============================================================

  /// Check if a room can be claimed by an owner
  /// Room must have: ownerId == null AND status == 'active'
  Future<bool> canRoomBeClaimed(String roomId) async {
    try {
      final roomDoc = await _firestore.collection(_collection).doc(roomId).get();
      if (!roomDoc.exists) return false;
      
      final data = roomDoc.data()!;
      final ownerId = data['ownerId'];
      final status = data['status'] ?? 'active';
      
      // Room can only be claimed if no owner and active
      return ownerId == null && status == 'active';
    } catch (e) {
      print('❌ Error checking if room can be claimed: $e');
      return false;
    }
  }

  /// Check if owner already has a pending claim for this room
  Future<bool> hasOwnerPendingClaim(String roomId, String ownerId) async {
    try {
      final query = await _firestore
          .collection(_ownershipRequestsCollection)
          .where('roomId', isEqualTo: roomId)
          .where('ownerId', isEqualTo: ownerId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      
      return query.docs.isNotEmpty;
    } catch (e) {
      print('❌ Error checking pending ownership claim: $e');
      return false;
    }
  }

  /// Create ownership request for a room
  /// IMPORTANT: This does NOT create a new room or modify existing room
  /// Status starts as 'pending' - room creator must approve
  Future<String?> createOwnershipRequest(String roomId) async {
    final user = AuthService().currentUser;
    if (user == null) {
      print('❌ Cannot create ownership request: Not authenticated');
      return null;
    }

    try {
      // Verify room can be claimed
      final canClaim = await canRoomBeClaimed(roomId);
      if (!canClaim) {
        print('❌ Room cannot be claimed: Either already has owner or inactive');
        return null;
      }

      // Check for existing pending claim by this owner
      final hasPending = await hasOwnerPendingClaim(roomId, user.uid);
      if (hasPending) {
        print('❌ Owner already has pending claim for this room');
        return null;
      }

      // Create the ownership request
      final docRef = _firestore.collection(_ownershipRequestsCollection).doc();
      final request = RoomOwnershipRequestModel(
        requestId: docRef.id,
        roomId: roomId,
        ownerId: user.uid,
        status: OwnershipRequestStatus.pending,
        requestedAt: DateTime.now(),
      );

      await docRef.set(request.toMap());
      print('✅ Ownership request created: ${docRef.id}');

      // Notify room admin/creator about the claim request
      final roomDoc = await _firestore.collection(_collection).doc(roomId).get();
      if (roomDoc.exists) {
        final roomData = roomDoc.data()!;
        final creatorId = roomData['createdBy'];
        if (creatorId != null && creatorId != user.uid) {
          await _notificationService.sendOwnershipClaimNotification(
            roomId: roomId,
            roomName: roomData['name'] ?? 'Unknown Room',
            ownerId: user.uid,
            creatorId: creatorId,
            requestId: docRef.id,
          );
        }
      }

      return docRef.id;
    } catch (e) {
      print('❌ Error creating ownership request: $e');
      return null;
    }
  }

  /// Approve ownership request
  /// CRITICAL: This ONLY updates room.ownerId and creationType
  /// Does NOT: merge rooms, move users, copy data, or delete anything
  Future<bool> approveOwnershipRequest(String requestId) async {
    final currentUser = AuthService().currentUser;
    if (currentUser == null) return false;

    try {
      // Get the request
      final requestDoc = await _firestore
          .collection(_ownershipRequestsCollection)
          .doc(requestId)
          .get();
      
      if (!requestDoc.exists) {
        print('❌ Ownership request not found');
        return false;
      }

      final request = RoomOwnershipRequestModel.fromFirestore(requestDoc);
      
      if (!request.isPending) {
        print('❌ Request is not pending');
        return false;
      }

      // Verify current user is room creator (admin)
      final roomDoc = await _firestore.collection(_collection).doc(request.roomId).get();
      if (!roomDoc.exists) {
        print('❌ Room not found');
        return false;
      }

      final roomData = roomDoc.data()!;
      final creatorId = roomData['createdBy'];
      
      if (creatorId != currentUser.uid) {
        print('❌ Only room creator can approve ownership requests');
        return false;
      }

      // Verify room still has no owner
      if (roomData['ownerId'] != null) {
        print('❌ Room already has an owner');
        return false;
      }

      // Use batch to update both atomically
      final batch = _firestore.batch();

      // Update the request
      batch.update(requestDoc.reference, {
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'reviewedBy': currentUser.uid,
      });

      // Update the room - ONLY these fields, nothing else
      batch.update(roomDoc.reference, {
        'ownerId': request.ownerId,
        'creationType': 'owner_created',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      print('✅ Ownership request approved. Room owner set to: ${request.ownerId}');

      // Clear cache to reflect changes
      clearCache();

      // Notify the owner about approval
      await _notificationService.sendOwnershipApprovedNotification(
        roomId: request.roomId,
        roomName: roomData['name'] ?? 'Unknown Room',
        ownerId: request.ownerId,
      );

      return true;
    } catch (e) {
      print('❌ Error approving ownership request: $e');
      return false;
    }
  }

  /// Reject ownership request
  Future<bool> rejectOwnershipRequest(String requestId) async {
    final currentUser = AuthService().currentUser;
    if (currentUser == null) return false;

    try {
      final requestDoc = await _firestore
          .collection(_ownershipRequestsCollection)
          .doc(requestId)
          .get();
      
      if (!requestDoc.exists) {
        print('❌ Ownership request not found');
        return false;
      }

      final request = RoomOwnershipRequestModel.fromFirestore(requestDoc);
      
      if (!request.isPending) {
        print('❌ Request is not pending');
        return false;
      }

      // Verify current user is room creator
      final roomDoc = await _firestore.collection(_collection).doc(request.roomId).get();
      if (!roomDoc.exists) return false;

      final creatorId = roomDoc.data()?['createdBy'];
      if (creatorId != currentUser.uid) {
        print('❌ Only room creator can reject ownership requests');
        return false;
      }

      // Update the request
      await requestDoc.reference.update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'reviewedBy': currentUser.uid,
      });

      print('✅ Ownership request rejected');

      // Notify the owner about rejection
      await _notificationService.sendOwnershipRejectedNotification(
        roomId: request.roomId,
        roomName: roomDoc.data()?['name'] ?? 'Unknown Room',
        ownerId: request.ownerId,
      );

      return true;
    } catch (e) {
      print('❌ Error rejecting ownership request: $e');
      return false;
    }
  }

  /// Get pending ownership requests for a room (for room admin)
  Future<List<RoomOwnershipRequestModel>> getPendingOwnershipRequests(String roomId) async {
    try {
      final query = await _firestore
          .collection(_ownershipRequestsCollection)
          .where('roomId', isEqualTo: roomId)
          .where('status', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .get();

      return query.docs
          .map((doc) => RoomOwnershipRequestModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Error getting pending ownership requests: $e');
      return [];
    }
  }

  /// Get ownership requests made by current user
  Future<List<RoomOwnershipRequestModel>> getMyOwnershipRequests() async {
    final user = AuthService().currentUser;
    if (user == null) return [];

    try {
      final query = await _firestore
          .collection(_ownershipRequestsCollection)
          .where('ownerId', isEqualTo: user.uid)
          .orderBy('requestedAt', descending: true)
          .get();

      return query.docs
          .map((doc) => RoomOwnershipRequestModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Error getting my ownership requests: $e');
      return [];
    }
  }

  /// Stream of pending ownership requests for rooms where current user is admin
  Stream<List<RoomOwnershipRequestModel>> streamPendingOwnershipRequestsForAdmin() {
    final user = AuthService().currentUser;
    if (user == null) return Stream.value([]);

    // First get rooms where user is creator, then get pending requests for those
    return _firestore
        .collection(_collection)
        .where('createdBy', isEqualTo: user.uid)
        .snapshots()
        .asyncMap((roomsSnapshot) async {
      if (roomsSnapshot.docs.isEmpty) return <RoomOwnershipRequestModel>[];

      final roomIds = roomsSnapshot.docs.map((d) => d.id).toList();
      
      // Get pending requests for all rooms user created
      final List<RoomOwnershipRequestModel> allRequests = [];
      for (final roomId in roomIds) {
        final requests = await getPendingOwnershipRequests(roomId);
        allRequests.addAll(requests);
      }
      
      return allRequests;
    });
  }

  /// Check if room has an owner
  Future<bool> roomHasOwner(String roomId) async {
    try {
      final roomDoc = await _firestore.collection(_collection).doc(roomId).get();
      if (!roomDoc.exists) return false;
      return roomDoc.data()?['ownerId'] != null;
    } catch (e) {
      return false;
    }
  }

  /// Get room owner details
  Future<Map<String, dynamic>?> getRoomOwnerDetails(String roomId) async {
    try {
      final roomDoc = await _firestore.collection(_collection).doc(roomId).get();
      if (!roomDoc.exists) return null;
      
      final ownerId = roomDoc.data()?['ownerId'];
      if (ownerId == null) return null;

      final ownerDoc = await _firestore.collection('users').doc(ownerId).get();
      if (!ownerDoc.exists) return null;

      return {'id': ownerId, ...ownerDoc.data()!};
    } catch (e) {
      print('❌ Error getting room owner details: $e');
      return null;
    }
  }

  // ============================================================
  // STEP-4: OWNER-CREATED ROOMS + JOIN REQUESTS
  // ============================================================

  /// Create a room as an owner (roomType = owner_created, ownerId set directly)
  /// This is different from createGroup which creates user-owned rooms
  Future<String?> createOwnerRoom({
    required String name,
    required String description,
    required String location,
    double? lat,
    double? lng,
    required int maxMembers,
    required double rentAmount,
    required String rentCurrency,
    required double advanceAmount,
    required String roomType,
    required List<String> amenities,
    List<File> imageFiles = const [],
    List<XFile> webPickedFiles = const [],
  }) async {
    final user = AuthService().currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Check if user already has a room
    final canCreate = await canUserCreateGroup();
    if (!canCreate) {
      throw Exception('You can only create or join one group at a time');
    }

    final docRef = _firestore.collection(_collection).doc();
    final List<String> imageUrls = [];

    // Upload images
    if (!kIsWeb && imageFiles.isNotEmpty) {
      for (var index = 0; index < imageFiles.length; index++) {
        final file = imageFiles[index];
        final url = await _cloudinary.uploadFile(
          file: file,
          folder: CloudinaryFolder.groups,
          publicId: 'group_${docRef.id}_${index + 1}',
          context: {'groupId': docRef.id, 'createdBy': user.uid},
        );
        if (url != null) {
          imageUrls.add(url);
        }
      }
    } else if (kIsWeb && webPickedFiles.isNotEmpty) {
      for (var index = 0; index < webPickedFiles.length; index++) {
        final image = webPickedFiles[index];
        final bytes = await image.readAsBytes();
        final url = await _cloudinary.uploadBytes(
          bytes: bytes,
          fileName: image.name,
          folder: CloudinaryFolder.groups,
          publicId: 'group_${docRef.id}_${index + 1}',
          context: {'groupId': docRef.id, 'createdBy': user.uid},
        );
        if (url != null) {
          imageUrls.add(url);
        }
      }
    }

    final rentDetails = {
      'amount': rentAmount,
      'currency': rentCurrency,
      'advanceAmount': advanceAmount,
    };

    final data = {
      'id': docRef.id,
      'name': name.trim(),
      'description': description.trim(),
      'location': location.trim(),
      'lat': lat,
      'lng': lng,
      'memberCount': 0, // Owner-created rooms start empty
      'maxMembers': maxMembers,
      'rent': rentDetails,
      'rentAmount': rentAmount,
      'rentCurrency': rentCurrency,
      'advanceAmount': advanceAmount,
      'roomType': roomType,
      'amenities': amenities,
      'imageUrl': imageUrls.isNotEmpty ? imageUrls.first : null,
      'images': imageUrls,
      'imageCount': imageUrls.length,
      'createdBy': user.uid,
      'members': [], // No members initially (owner is NOT a roommate)
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      // === OWNER-CREATED ROOM FIELDS ===
      'status': 'active',
      'isPublic': true,
      'creationType': 'owner_created',
      'ownerId': user.uid, // Owner set directly
    };

    await docRef.set(data);
    
    print('✅ Owner-created room: ${docRef.id}');
    clearCache();
    
    return docRef.id;
  }

  /// Check if user can request to join a room
  Future<Map<String, dynamic>> canRequestToJoin(String roomId) async {
    final user = AuthService().currentUser;
    if (user == null) {
      return {'canJoin': false, 'reason': 'Not authenticated'};
    }

    try {
      final roomDoc = await _firestore.collection(_collection).doc(roomId).get();
      if (!roomDoc.exists) {
        return {'canJoin': false, 'reason': 'Room not found'};
      }

      final roomData = roomDoc.data()!;

      // Check room is active and public
      if (roomData['status'] != 'active') {
        return {'canJoin': false, 'reason': 'Room is not active'};
      }
      if (roomData['isPublic'] != true) {
        return {'canJoin': false, 'reason': 'Room is not public'};
      }

      // Check user is not the owner
      if (roomData['ownerId'] == user.uid) {
        return {'canJoin': false, 'reason': 'You are the owner of this room'};
      }

      // Check user is not already a member - query USER_ROOM_LINK
      final existingMembership = await _firestore
          .collection(_roomMembersCollection)
          .where('roomId', isEqualTo: roomId)
          .where('userId', isEqualTo: user.uid)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      
      if (existingMembership.docs.isNotEmpty) {
        return {'canJoin': false, 'reason': 'You are already a member'};
      }

      // Check user doesn't have a pending request
      final existingRequest = await _firestore
          .collection(_joinRequestsCollection)
          .where('roomId', isEqualTo: roomId)
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (existingRequest.docs.isNotEmpty) {
        return {'canJoin': false, 'reason': 'You already have a pending request'};
      }

      // Check room is not full - query USER_ROOM_LINK for actual count
      final maxMembers = roomData['maxMembers'] ?? 4;
      final activeMembersQuery = await _firestore
          .collection(_roomMembersCollection)
          .where('roomId', isEqualTo: roomId)
          .where('isActive', isEqualTo: true)
          .get();
      final currentMemberCount = activeMembersQuery.docs.length;
      
      if (currentMemberCount >= maxMembers) {
        return {'canJoin': false, 'reason': 'Room is full'};
      }

      return {'canJoin': true, 'reason': null};
    } catch (e) {
      print('❌ Error checking join eligibility: $e');
      return {'canJoin': false, 'reason': 'Error checking eligibility'};
    }
  }

  /// Request to join a room
  /// RULE: Do NOT create USER_ROOM_LINK yet - only create join request
  Future<String?> requestToJoinRoom(String roomId) async {
    final user = AuthService().currentUser;
    if (user == null) return null;

    try {
      // Verify user can request to join
      final eligibility = await canRequestToJoin(roomId);
      if (eligibility['canJoin'] != true) {
        print('❌ Cannot request to join: ${eligibility['reason']}');
        return null;
      }

      // Create join request
      final requestDoc = _firestore.collection(_joinRequestsCollection).doc();
      final requestData = {
        'roomId': roomId,
        'userId': user.uid,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
      };

      await requestDoc.set(requestData);
      print('✅ Join request created: ${requestDoc.id}');

      // Notify room owner
      final roomDoc = await _firestore.collection(_collection).doc(roomId).get();
      if (roomDoc.exists) {
        final ownerId = roomDoc.data()?['ownerId'];
        final roomName = roomDoc.data()?['name'] ?? 'Unknown Room';
        if (ownerId != null) {
          await _notificationService.sendJoinRequestNotification(
            roomId: roomId,
            roomName: roomName,
            ownerId: ownerId,
            requesterId: user.uid,
          );
        }
      }

      return requestDoc.id;
    } catch (e) {
      print('❌ Error creating join request: $e');
      return null;
    }
  }

  /// Approve join request (owner only) - STEP-4
  /// CRITICAL: Atomic batch - create USER_ROOM_LINK and update request
  Future<bool> approveOwnerJoinRequest(String requestId) async {
    final currentUser = AuthService().currentUser;
    if (currentUser == null) return false;

    try {
      // Get the request
      final requestDoc = await _firestore
          .collection(_joinRequestsCollection)
          .doc(requestId)
          .get();
      
      if (!requestDoc.exists) {
        print('❌ Join request not found');
        return false;
      }

      final request = RoomJoinRequestModel.fromFirestore(requestDoc);
      
      if (!request.isPending) {
        print('❌ Request is not pending');
        return false;
      }

      // Verify current user is room owner
      final roomDoc = await _firestore.collection(_collection).doc(request.roomId).get();
      if (!roomDoc.exists) {
        print('❌ Room not found');
        return false;
      }

      final roomData = roomDoc.data()!;
      final ownerId = roomData['ownerId'];
      
      if (ownerId != currentUser.uid) {
        print('❌ Only room owner can approve join requests');
        return false;
      }

      // Check room is not full - query USER_ROOM_LINK for actual count
      final maxMembers = roomData['maxMembers'] ?? 4;
      final activeMembersQuery = await _firestore
          .collection(_roomMembersCollection)
          .where('roomId', isEqualTo: request.roomId)
          .where('isActive', isEqualTo: true)
          .get();
      final currentMemberCount = activeMembersQuery.docs.length;
      
      if (currentMemberCount >= maxMembers) {
        print('❌ Room is full');
        return false;
      }

      // Use batch to update atomically
      final batch = _firestore.batch();

      // 1. Update the join request
      batch.update(requestDoc.reference, {
        'status': 'approved',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': currentUser.uid,
      });

      // 2. Create USER_ROOM_LINK (room_members record) - SINGLE SOURCE OF TRUTH
      // NOTE: Do NOT update room.members[] - membership tracked ONLY via room_members
      final memberDocRef = _firestore.collection(_roomMembersCollection).doc();
      batch.set(memberDocRef, {
        'roomId': request.roomId,
        'userId': request.userId,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      await batch.commit();
      print('✅ Join request approved. User ${request.userId} is now a member.');

      // Clear cache
      clearCache();

      // Notify the user about approval
      await _notificationService.sendJoinRequestApprovedNotification(
        roomId: request.roomId,
        roomName: roomData['name'] ?? 'Unknown Room',
        userId: request.userId,
      );

      return true;
    } catch (e) {
      print('❌ Error approving join request: $e');
      return false;
    }
  }

  /// Reject join request (owner only) - STEP-4
  Future<bool> rejectOwnerJoinRequest(String requestId) async {
    final currentUser = AuthService().currentUser;
    if (currentUser == null) return false;

    try {
      final requestDoc = await _firestore
          .collection(_joinRequestsCollection)
          .doc(requestId)
          .get();
      
      if (!requestDoc.exists) {
        print('❌ Join request not found');
        return false;
      }

      final request = RoomJoinRequestModel.fromFirestore(requestDoc);
      
      if (!request.isPending) {
        print('❌ Request is not pending');
        return false;
      }

      // Verify current user is room owner
      final roomDoc = await _firestore.collection(_collection).doc(request.roomId).get();
      if (!roomDoc.exists) return false;

      final ownerId = roomDoc.data()?['ownerId'];
      if (ownerId != currentUser.uid) {
        print('❌ Only room owner can reject join requests');
        return false;
      }

      // Update the request
      await requestDoc.reference.update({
        'status': 'rejected',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': currentUser.uid,
      });

      print('✅ Join request rejected');

      // Notify the user about rejection
      await _notificationService.sendJoinRequestRejectedNotification(
        roomId: request.roomId,
        roomName: roomDoc.data()?['name'] ?? 'Unknown Room',
        userId: request.userId,
      );

      return true;
    } catch (e) {
      print('❌ Error rejecting join request: $e');
      return false;
    }
  }

  /// Get pending join requests for a room (owner view)
  Future<List<RoomJoinRequestModel>> getPendingJoinRequests(String roomId) async {
    try {
      final query = await _firestore
          .collection(_joinRequestsCollection)
          .where('roomId', isEqualTo: roomId)
          .where('status', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .get();

      return query.docs
          .map((doc) => RoomJoinRequestModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Error getting pending join requests: $e');
      return [];
    }
  }

  /// Get join requests made by current user
  Future<List<RoomJoinRequestModel>> getMyJoinRequests() async {
    final user = AuthService().currentUser;
    if (user == null) return [];

    try {
      final query = await _firestore
          .collection(_joinRequestsCollection)
          .where('userId', isEqualTo: user.uid)
          .orderBy('requestedAt', descending: true)
          .get();

      return query.docs
          .map((doc) => RoomJoinRequestModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Error getting my join requests: $e');
      return [];
    }
  }

  /// Stream of pending join requests for rooms where current user is owner
  Stream<List<RoomJoinRequestModel>> streamPendingJoinRequestsForOwner() {
    final user = AuthService().currentUser;
    if (user == null) return Stream.value([]);

    // Get rooms where user is owner, then get pending requests
    return _firestore
        .collection(_collection)
        .where('ownerId', isEqualTo: user.uid)
        .snapshots()
        .asyncMap((roomsSnapshot) async {
      if (roomsSnapshot.docs.isEmpty) return <RoomJoinRequestModel>[];

      final roomIds = roomsSnapshot.docs.map((d) => d.id).toList();
      
      final List<RoomJoinRequestModel> allRequests = [];
      for (final roomId in roomIds) {
        final requests = await getPendingJoinRequests(roomId);
        allRequests.addAll(requests);
      }
      
      return allRequests;
    });
  }

  /// Check if current user is the owner of a room
  Future<bool> isRoomOwner(String roomId) async {
    final user = AuthService().currentUser;
    if (user == null) return false;

    try {
      final roomDoc = await _firestore.collection(_collection).doc(roomId).get();
      if (!roomDoc.exists) return false;
      return roomDoc.data()?['ownerId'] == user.uid;
    } catch (e) {
      return false;
    }
  }

  /// Get owner-created public rooms that user can join
  Future<List<Map<String, dynamic>>> getAvailableOwnerRooms() async {
    final user = AuthService().currentUser;
    if (user == null) return [];

    try {
      final query = await _firestore
          .collection(_collection)
          .where('status', isEqualTo: 'active')
          .where('isPublic', isEqualTo: true)
          .where('creationType', isEqualTo: 'owner_created')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      // Filter out rooms where user is owner or already a member
      return query.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where((room) {
            if (room['ownerId'] == user.uid) return false;
            final members = List<String>.from(room['members'] ?? []);
            return !members.contains(user.uid);
          })
          .toList();
    } catch (e) {
      print('❌ Error getting available owner rooms: $e');
      return [];
    }
  }
}


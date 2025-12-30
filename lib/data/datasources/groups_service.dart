import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:roomie/data/datasources/cloudinary_service.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:roomie/data/datasources/notification_service.dart';

/// Singleton service for group operations with caching
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

  // Cache for current user's group
  Map<String, dynamic>? _currentGroupCache;
  DateTime? _currentGroupCacheTime;
  static const Duration _cacheExpiry = Duration(minutes: 2);

  /// Clear cache (call on logout or group change)
  void clearCache() {
    _currentGroupCache = null;
    _currentGroupCacheTime = null;
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
    };

    await docRef.set(data);
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
      return null;
    }

    // Return cached data if valid and not forcing refresh
    if (!forceRefresh && 
        _currentGroupCache != null && 
        _currentGroupCacheTime != null &&
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
      // Update cache
      _currentGroupCache = groupData;
      _currentGroupCacheTime = DateTime.now();
      print('Current user group: ${groupData['name']} (${groupData['id']})');
      return groupData;
    }

    // Cache the null result too
    _currentGroupCache = null;
    _currentGroupCacheTime = DateTime.now();
    print('No current group found for user');
    return null;
  }

  // Check if user can create a new group (hasn't created or joined any)
  Future<bool> canUserCreateGroup() async {
    final currentGroup = await getCurrentUserGroup();
    return currentGroup == null;
  }

  // Get available groups (excluding user's current group)
  Future<List<Map<String, dynamic>>> getAvailableGroups() async {
    final user = AuthService().currentUser;
    if (user == null) {
      print('No user authenticated for getAvailableGroups');
      return [];
    }

    print('Getting available groups for user: ${user.uid}');

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
          print(
            'Group ${group['name']}: members=$members, userIsMember=$isUserMember',
          );
          return !isUserMember; // Exclude groups user is already in
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

    await _updateGroupChatMembers(groupId);
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
  }

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

        // If the group is now empty, delete it completely.
        // Otherwise, just update the member list and count.
        if (members.isEmpty) {
          // Delete the group document completely when no members left
          tx.delete(ref);
        } else {
          tx.update(ref, {
            'members': members,
            'memberCount': members.length,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        // This case should ideally not happen if UI is correct
        throw Exception('User is not a member of this group');
      }
    });

    // Clean up related data if group was deleted (members empty)
    final groupDoc = await ref.get();
    if (!groupDoc.exists) {
      // Group was deleted, so clean up related collections
      await _cleanupGroupData(groupId);
    }
  }

  /// Helper method to clean up all related data when a group is deleted
  Future<void> _cleanupGroupData(String groupId) async {
    try {
      // Delete all join requests for this group
      final joinRequestsQuery = await _firestore
          .collection('joinRequests')
          .where('groupId', isEqualTo: groupId)
          .get();
      
      for (var doc in joinRequestsQuery.docs) {
        await doc.reference.delete();
      }

      // Delete group chat messages
      final messagesQuery = await _firestore
          .collection('chats')
          .doc(groupId)
          .collection('messages')
          .get();
      
      for (var doc in messagesQuery.docs) {
        await doc.reference.delete();
      }

      // Delete the chat document itself
      await _firestore.collection('chats').doc(groupId).delete();

      print('Successfully cleaned up all data for deleted group: $groupId');
    } catch (e) {
      print('Error cleaning up group data: $e');
      // Don't throw error as the main group deletion already succeeded
    }
  }

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

  Future<bool> deleteGroup(String groupId) async {
    final ref = _firestore.collection(_collection).doc(groupId);
    await ref.update({
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        });
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
}

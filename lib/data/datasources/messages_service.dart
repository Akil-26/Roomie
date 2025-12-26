import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:roomie/data/datasources/auth_service.dart';

class MessagesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _realtimeDB = FirebaseDatabase.instance;
  final AuthService _authService = AuthService();

  // ========== LOCAL CACHE FOR INSTANT LOAD ==========
  static List<Map<String, dynamic>> _cachedConversations = [];
  static final _conversationsController = StreamController<List<Map<String, dynamic>>>.broadcast();
  static bool _isListening = false;
  static StreamSubscription? _groupsSubscription;
  static StreamSubscription? _chatsSubscription;
  static StreamSubscription? _groupChatsSubscription;

  // 📱 Get all conversations for the current user (both group and individual)
  // Now uses local cache + real-time listeners for WhatsApp-like instant load
  Stream<List<Map<String, dynamic>>> getAllConversations() {
    final user = _authService.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    // Emit cached data immediately if available (instant load like WhatsApp)
    if (_cachedConversations.isNotEmpty) {
      Future.microtask(() => _conversationsController.add(_cachedConversations));
    }

    // Start real-time listeners if not already listening
    if (!_isListening) {
      _startRealtimeListeners(user.uid);
    }

    // Also do a fresh fetch in background to ensure data is up-to-date
    _refreshConversations(user.uid);

    return _conversationsController.stream;
  }

  // Start real-time listeners for instant updates
  void _startRealtimeListeners(String userId) {
    if (_isListening) return;
    _isListening = true;

    // Listen to user's groups changes
    _groupsSubscription = _firestore
        .collection('groups')
        .where('members', arrayContains: userId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((_) => _refreshConversations(userId));

    // Listen to individual chats changes
    _chatsSubscription = _realtimeDB
        .ref('chats')
        .onChildChanged
        .listen((_) => _refreshConversations(userId));

    // Listen to group chats changes
    _groupChatsSubscription = _realtimeDB
        .ref('groupChats')
        .onChildChanged
        .listen((_) => _refreshConversations(userId));
  }

  // Refresh conversations with debouncing
  Timer? _refreshDebouncer;
  Future<void> _refreshConversations(String userId) async {
    // Debounce rapid updates
    _refreshDebouncer?.cancel();
    _refreshDebouncer = Timer(const Duration(milliseconds: 300), () async {
      final conversations = await _getConversations(userId);
      _cachedConversations = conversations;
      _conversationsController.add(conversations);
    });
  }

  // Dispose listeners when not needed
  void dispose() {
    _groupsSubscription?.cancel();
    _chatsSubscription?.cancel();
    _groupChatsSubscription?.cancel();
    _isListening = false;
  }

  // Force refresh (e.g., pull to refresh)
  Future<void> forceRefresh() async {
    final user = _authService.currentUser;
    if (user == null) return;
    
    final conversations = await _getConversations(user.uid);
    _cachedConversations = conversations;
    _conversationsController.add(conversations);
  }

  // 🔄 Get conversations by combining group and individual chats
  Future<List<Map<String, dynamic>>> _getConversations(String userId) async {
    List<Map<String, dynamic>> conversations = [];

    try {
      print('🔄 Loading conversations for user: $userId');

      // 1. Get Group Conversations (both from membership and from chat participation)
      final groupConversations = await _getGroupConversations(userId);
      print('👥 Got ${groupConversations.length} group conversations');
      conversations.addAll(groupConversations);

      // 2. Get Additional Group Chats where user has participated (but may not be official member)
      final participatedGroupChats = await _getParticipatedGroupChats(userId);
      print('💬 Got ${participatedGroupChats.length} participated group chats');
      conversations.addAll(participatedGroupChats);

      // 3. Get Individual Conversations (Direct Messages)
      final individualConversations = await _getIndividualConversations(userId);
      print(
        '👤 Got ${individualConversations.length} individual conversations',
      );
      conversations.addAll(individualConversations);

      // 4. Remove duplicates based on conversation ID
      final uniqueConversations = <String, Map<String, dynamic>>{};
      for (final conv in conversations) {
        final id = conv['id'] as String;
        if (!uniqueConversations.containsKey(id) ||
            (conv['lastMessageTime'] != null &&
                uniqueConversations[id]?['lastMessageTime'] != null &&
                (conv['lastMessageTime'] as DateTime).isAfter(
                  uniqueConversations[id]!['lastMessageTime'] as DateTime,
                ))) {
          uniqueConversations[id] = conv;
        }
      }

      final finalConversations = uniqueConversations.values.toList();
      print('📊 Total unique conversations: ${finalConversations.length}');

      // 5. Sort by last message time (most recent first)
      finalConversations.sort((a, b) {
        final aTime = a['lastMessageTime'] as DateTime?;
        final bTime = b['lastMessageTime'] as DateTime?;

        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;

        return bTime.compareTo(aTime);
      });

      print('✅ Returning ${finalConversations.length} sorted conversations');
      return finalConversations;
    } catch (e) {
      print('❌ Error getting conversations: $e');
      return [];
    }
  }

  // 🏠 Get Group Conversations
  Future<List<Map<String, dynamic>>> _getGroupConversations(
    String userId,
  ) async {
    try {
      print('🔍 Getting group conversations for user: $userId');

      // Get user's current group
      final userGroupQuery =
          await _firestore
              .collection('groups')
              .where('members', arrayContains: userId)
              .where('isActive', isEqualTo: true)
              .get();

      print('📊 Found ${userGroupQuery.docs.length} groups for user');

      if (userGroupQuery.docs.isEmpty) {
        print('❌ User is not in any groups');
        return [];
      }

      List<Map<String, dynamic>> groupConversations = [];

      for (final groupDoc in userGroupQuery.docs) {
        final groupData = groupDoc.data();
        final groupId = groupDoc.id;

        print('👥 Processing group: ${groupData['name']} (ID: $groupId)');

        // Get the latest message from this group (optional - group shows even without messages)
        final messagesRef = _realtimeDB.ref('groupChats/$groupId/messages');
        final snapshot =
            await messagesRef.orderByChild('timestamp').limitToLast(1).get();

        Map<String, dynamic>? lastMessage;
        DateTime? lastMessageTime;
        String lastMessageText = 'Start a conversation...';

        if (snapshot.exists && snapshot.value != null) {
          final messages = Map<String, dynamic>.from(snapshot.value as Map);
          if (messages.isNotEmpty) {
            final lastMessageData = messages.values.last;
            lastMessage = Map<String, dynamic>.from(lastMessageData);

            if (lastMessage['timestamp'] != null) {
              lastMessageTime = DateTime.fromMillisecondsSinceEpoch(
                lastMessage['timestamp'] as int,
              );
              lastMessageText = lastMessage['message'] ?? 'Message';
            }

            print('💬 Last message: ${lastMessage['message']}');
          }
        } else {
          print('📭 No messages found in group chat - showing anyway');
          // Set default time to group creation time if available
          if (groupData['createdAt'] != null) {
            lastMessageTime = (groupData['createdAt'] as Timestamp).toDate();
          }
        }

        groupConversations.add({
          'id': groupId,
          'name': groupData['name'] ?? 'Group Chat',
          'type': 'group',
          'imageUrl': groupData['imageUrl'],
          'members': groupData['members'] ?? [],
          'memberCount': groupData['memberCount'] ?? 1,
          'lastMessage': lastMessageText,
          'lastMessageSender': lastMessage?['senderName'] ?? '',
          'lastMessageTime': lastMessageTime ?? DateTime.now(),
          'unreadCount': 0,
          'groupData': groupData,
        });
      }

      print('✅ Returning ${groupConversations.length} group conversations');
      return groupConversations;
    } catch (e) {
      print('❌ Error getting group conversations: $e');
      return [];
    }
  }

  // � Get Group Chats where user has participated (regardless of membership)
  Future<List<Map<String, dynamic>>> _getParticipatedGroupChats(
    String userId,
  ) async {
    try {
      print('🔍 Getting participated group chats for user: $userId');

      // Check all group chats in Realtime Database
      final groupChatsRef = _realtimeDB.ref('groupChats');
      final snapshot = await groupChatsRef.get();

      if (!snapshot.exists || snapshot.value == null) {
        print('📭 No group chats found in Realtime Database');
        return [];
      }

      final allGroupChats = Map<String, dynamic>.from(snapshot.value as Map);
      List<Map<String, dynamic>> participatedChats = [];

      for (final entry in allGroupChats.entries) {
        final groupId = entry.key;
        final groupChatData = Map<String, dynamic>.from(entry.value);

        // Check if user has sent messages in this group
        final messages = groupChatData['messages'];
        bool hasParticipated = false;
        Map<String, dynamic>? lastMessage;
        DateTime? lastMessageTime;

        if (messages != null && messages is Map) {
          final messageMap = Map<String, dynamic>.from(messages);

          // Check if user has sent any messages
          for (final msgEntry in messageMap.entries) {
            final message = Map<String, dynamic>.from(msgEntry.value as Map);
            if (message['senderId'] == userId) {
              hasParticipated = true;
              break;
            }
          }

          // Get the most recent message
          if (messageMap.isNotEmpty) {
            final sortedMessages =
                messageMap.entries.toList()..sort((a, b) {
                  final aMap = Map<String, dynamic>.from(a.value as Map);
                  final bMap = Map<String, dynamic>.from(b.value as Map);
                  final aTime = aMap['timestamp'] as int? ?? 0;
                  final bTime = bMap['timestamp'] as int? ?? 0;
                  return bTime.compareTo(aTime);
                });

            if (sortedMessages.isNotEmpty) {
              lastMessage = Map<String, dynamic>.from(
                sortedMessages.first.value as Map,
              );
              final timestamp = lastMessage['timestamp'] as int?;
              if (timestamp != null) {
                lastMessageTime = DateTime.fromMillisecondsSinceEpoch(
                  timestamp,
                );
              }
            }
          }
        }

        if (hasParticipated) {
          print('📱 Found participated group chat: $groupId');

          // Get group details from Firestore
          try {
            final groupDoc =
                await _firestore.collection('groups').doc(groupId).get();
            final groupData = groupDoc.data() ?? {};

            participatedChats.add({
              'id': groupId,
              'name': groupData['name'] ?? 'Group Chat',
              'type': 'group',
              'imageUrl': groupData['imageUrl'],
              'members': groupData['members'] ?? [],
              'memberCount': groupData['memberCount'] ?? 1,
              'lastMessage':
                  lastMessage?['message'] ?? 'Start a conversation...',
              'lastMessageSender': lastMessage?['senderName'] ?? '',
              'lastMessageTime': lastMessageTime ?? DateTime.now(),
              'unreadCount': 0,
              'groupData': groupData,
            });
          } catch (e) {
            print('❌ Error fetching group details for $groupId: $e');
            // Add with minimal info if group details fetch fails
            participatedChats.add({
              'id': groupId,
              'name': 'Group Chat',
              'type': 'group',
              'imageUrl': null,
              'members': [],
              'memberCount': 1,
              'lastMessage':
                  lastMessage?['message'] ?? 'Start a conversation...',
              'lastMessageSender': lastMessage?['senderName'] ?? '',
              'lastMessageTime': lastMessageTime ?? DateTime.now(),
              'unreadCount': 0,
              'groupData': {},
            });
          }
        }
      }

      print('✅ Returning ${participatedChats.length} participated group chats');
      return participatedChats;
    } catch (e) {
      print('❌ Error getting participated group chats: $e');
      return [];
    }
  }

  // �👥 Get Individual Conversations (Person-to-Person)
  Future<List<Map<String, dynamic>>> _getIndividualConversations(
    String userId,
  ) async {
    try {
      // Get all individual chat rooms where this user is a participant
      final chatsRef = _realtimeDB.ref('chats');
      final snapshot = await chatsRef.get();

      if (!snapshot.exists || snapshot.value == null) {
        return [];
      }

      final allChats = Map<String, dynamic>.from(snapshot.value as Map);
      List<Map<String, dynamic>> conversations = [];

      for (final chatEntry in allChats.entries) {
        final chatId = chatEntry.key;
        final chatData = Map<String, dynamic>.from(chatEntry.value);

        // Check if current user is a participant
        final participants = List<String>.from(chatData['participants'] ?? []);
        if (!participants.contains(userId)) continue;

        // Get the other participant
        final otherParticipantId = participants.firstWhere(
          (id) => id != userId,
          orElse: () => '',
        );

        if (otherParticipantId.isEmpty) continue;

        // Get other participant's details from Firestore
        final userDoc =
            await _firestore.collection('users').doc(otherParticipantId).get();

        // Skip if user doesn't exist or has no data
        if (!userDoc.exists || userDoc.data() == null) {
          print(
            '⏭️ Skipping chat $chatId - user $otherParticipantId not found',
          );
          continue;
        }

        final userData = userDoc.data()!;

        // Skip if user has no name AND no email (invalid/test user)
        if ((userData['name'] == null ||
                userData['name'].toString().trim().isEmpty) &&
            (userData['email'] == null ||
                userData['email'].toString().trim().isEmpty)) {
          print('⏭️ Skipping chat $chatId - invalid user data (no name/email)');
          continue;
        }

        // Get latest message
        Map<String, dynamic>? lastMessage;
        DateTime? lastMessageTime;

        try {
          final messages = chatData['messages'];
          if (messages != null && messages is Map) {
            final messageMap = Map<String, dynamic>.from(messages);
            if (messageMap.isNotEmpty) {
              // Get the most recent message by sorting
              final sortedMessages =
                  messageMap.entries.toList()..sort((a, b) {
                    final aMap = Map<String, dynamic>.from(a.value as Map);
                    final bMap = Map<String, dynamic>.from(b.value as Map);
                    final aTime = aMap['timestamp'] as int? ?? 0;
                    final bTime = bMap['timestamp'] as int? ?? 0;
                    return bTime.compareTo(aTime);
                  });

              if (sortedMessages.isNotEmpty) {
                lastMessage = Map<String, dynamic>.from(
                  sortedMessages.first.value as Map,
                );
                final timestamp = lastMessage['timestamp'] as int?;
                if (timestamp != null) {
                  lastMessageTime = DateTime.fromMillisecondsSinceEpoch(
                    timestamp,
                  );
                }
              }
            }
          }
        } catch (e) {
          print('⚠️ Error parsing messages for chat $chatId: $e');
        }

        conversations.add({
          'id': chatId,
          'name': userData['username'] ?? userData['name'] ?? 'User',
          'type': 'individual',
          'imageUrl': userData['profileImageUrl'],
          'otherUserId': otherParticipantId,
          'lastMessage': lastMessage?['message'] ?? 'No messages yet',
          'lastMessageSender': lastMessage?['senderName'] ?? '',
          'lastMessageTime': lastMessageTime,
          'unreadCount': 0,
          'userData': userData, // Full user data for navigation
        });
      }

      return conversations;
    } catch (e) {
      print('Error getting individual conversations: $e');
      return [];
    }
  }

  // 🔄 Refresh conversations (force reload)
  Future<List<Map<String, dynamic>>> refreshConversations() async {
    final user = _authService.currentUser;
    if (user == null) {
      print('❌ No authenticated user for refreshConversations');
      return [];
    }

    print('🔄 Refreshing conversations for user: ${user.uid}');

    try {
      // Simple approach: Get all groups and check which ones have messages
      final conversations = <Map<String, dynamic>>[];

      // Check all groups in Firestore
      final allGroups = await _firestore.collection('groups').get();
      print('📊 Total groups in database: ${allGroups.docs.length}');

      for (final groupDoc in allGroups.docs) {
        final groupData = groupDoc.data();
        final groupId = groupDoc.id;
        final members = List<String>.from(groupData['members'] ?? []);

        print('👥 Checking group ${groupData['name']} (ID: $groupId)');
        print('   Members: $members');
        print('   User in group: ${members.contains(user.uid)}');

        // Check if user is a member OR has messages in this group
        bool shouldInclude = members.contains(user.uid);

        if (!shouldInclude) {
          // Check if user has sent messages in this group
          final messagesRef = _realtimeDB.ref('groupChats/$groupId/messages');
          final snapshot = await messagesRef.get();

          if (snapshot.exists && snapshot.value != null) {
            final messages = Map<String, dynamic>.from(snapshot.value as Map);
            for (final msgEntry in messages.entries) {
              final message = Map<String, dynamic>.from(msgEntry.value);
              if (message['senderId'] == user.uid) {
                shouldInclude = true;
                print('   Found user messages in group');
                break;
              }
            }
          }
        }

        if (shouldInclude) {
          // Get the latest message
          final messagesRef = _realtimeDB.ref('groupChats/$groupId/messages');
          final snapshot =
              await messagesRef.orderByChild('timestamp').limitToLast(1).get();

          String lastMessage = 'Start chatting...';
          DateTime lastMessageTime = DateTime.now();

          if (snapshot.exists && snapshot.value != null) {
            final messages = Map<String, dynamic>.from(snapshot.value as Map);
            if (messages.isNotEmpty) {
              final lastMsg = messages.values.last;
              lastMessage = lastMsg['message'] ?? 'Message';
              lastMessageTime = DateTime.fromMillisecondsSinceEpoch(
                lastMsg['timestamp'] as int,
              );
            }
          }

          conversations.add({
            'id': groupId,
            'name': groupData['name'] ?? 'Group Chat',
            'type': 'group',
            'imageUrl': groupData['imageUrl'],
            'members': members,
            'memberCount': members.length,
            'lastMessage': lastMessage,
            'lastMessageTime': lastMessageTime,
            'unreadCount': 0,
            'groupData': groupData,
          });

          print('✅ Added conversation: ${groupData['name']}');
        }
      }

      // Sort by last message time
      conversations.sort((a, b) {
        final aTime = a['lastMessageTime'] as DateTime;
        final bTime = b['lastMessageTime'] as DateTime;
        return bTime.compareTo(aTime);
      });

      print('🎉 Returning ${conversations.length} conversations');
      return conversations;
    } catch (e, stackTrace) {
      print('❌ Error refreshing conversations: $e');
      print('❌ Stack trace: $stackTrace');
      return [];
    }
  }

  // 🗑️ Delete conversation (for individual chats)
  Future<bool> deleteConversation(String conversationId, String type) async {
    try {
      if (type == 'individual') {
        await _realtimeDB.ref('chats/$conversationId').remove();
        return true;
      } else {
        // For group chats, we don't delete the conversation, just leave the group
        // This should be handled by the GroupsService
        return false;
      }
    } catch (e) {
      print('Error deleting conversation: $e');
      return false;
    }
  }

  // 📊 Get conversation statistics
  Future<Map<String, int>> getConversationStats(String userId) async {
    try {
      final conversations = await _getConversations(userId);

      int totalConversations = conversations.length;
      int groupConversations =
          conversations.where((c) => c['type'] == 'group').length;
      int individualConversations =
          conversations.where((c) => c['type'] == 'individual').length;
      int unreadMessages = conversations.fold(
        0,
        (total, c) => total + (c['unreadCount'] as int? ?? 0),
      );

      return {
        'total': totalConversations,
        'groups': groupConversations,
        'individual': individualConversations,
        'unread': unreadMessages,
      };
    } catch (e) {
      print('Error getting conversation stats: $e');
      return {'total': 0, 'groups': 0, 'individual': 0, 'unread': 0};
    }
  }
}

import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:roomie/data/models/message_model.dart';
import 'package:roomie/data/models/chat_model.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/cloudinary_service.dart';

class ChatService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final CloudinaryService _cloudinary = CloudinaryService();

  Future<String> uploadChatFile({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    String? folder,
  }) async {
    try {
      // Decide resource type based on contentType
      final type =
          contentType.startsWith('image/')
              ? CloudinaryResourceType.image
              : contentType.startsWith('video/')
              ? CloudinaryResourceType.video
              : CloudinaryResourceType.raw;

      final url = await _cloudinary.uploadBytes(
        bytes: bytes,
        fileName: fileName,
        folder: CloudinaryFolder.chat,
        publicId: null,
        context: {'scope': 'chat'},
        resourceType: type,
      );
      if (url == null) throw Exception('Cloudinary upload failed');
      return url;
    } catch (e) {
      debugPrint('Error uploading chat file: $e');
      rethrow;
    }
  }

  /// Create a new chat between two users
  Future<String> createOrGetChat({
    required String otherUserId,
    required String otherUserName,
    String? otherUserImageUrl,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Create a consistent chat ID based on user IDs (sorted)
      final participants = [currentUser.uid, otherUserId]..sort();
      final chatId = '${participants[0]}_${participants[1]}';

      final chatRef = _database.ref('chats/$chatId');
      final chatSnapshot = await chatRef.get();

      if (!chatSnapshot.exists) {
        // Create new chat - fetch current user's username from Firestore
        String currentUserDisplayName = 'You';
        try {
          final currentUserDoc = await _firestore
              .collection('users')
              .doc(currentUser.uid)
              .get();
          
          if (currentUserDoc.exists && currentUserDoc.data() != null) {
            final currentUserData = currentUserDoc.data()!;
            currentUserDisplayName = currentUserData['username'] as String? ??
                                    currentUserData['name'] as String? ??
                                    currentUser.email?.split('@')[0] ?? 
                                    'You';
          }
        } catch (e) {
          debugPrint('Error loading current user data: $e');
        }

        final chatData = ChatModel(
          id: chatId,
          participants: participants,
          participantNames: {
            currentUser.uid: currentUserDisplayName,
            otherUserId: otherUserName,
          },
          participantImages: {
            currentUser.uid: currentUser.photoURL,
            otherUserId: otherUserImageUrl,
          },
          unreadCounts: {currentUser.uid: 0, otherUserId: 0},
        );

        await chatRef.set(chatData.toMap());
        debugPrint('Created new chat: $chatId');
      }

      return chatId;
    } catch (e) {
      debugPrint('Error creating/getting chat: $e');
      rethrow;
    }
  }

  /// Send a message with rich content support
  Future<MessageModel> sendMessage({
    required String chatId,
    String? message,
    MessageType type = MessageType.text,
    List<MessageAttachment> attachments = const [],
    PollData? poll,
    TodoData? todo,
    Map<String, dynamic>? extraData,
    bool isSystemMessage = false,
    String? paymentRequestId,
    double? paymentAmount,
    List<String>? payToUserIds,
    String? paymentNote,
    String? paymentUpiId,
    String? payToPhoneNumber,
    Map<String, String>? paymentStatus,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null && !isSystemMessage) {
        throw Exception('User not authenticated');
      }

      final messageId = _database.ref('chats/$chatId/messages').push().key!;
      final now = DateTime.now();

      final chatRef = _database.ref('chats/$chatId');
      final chatSnapshot = await chatRef.get();

      String receiverId = '';
      Map<String, int> updatedUnreadCounts = {};
      ChatModel? chatData;

      if (chatSnapshot.exists) {
        chatData = ChatModel.fromMap(
          Map<String, dynamic>.from(chatSnapshot.value as Map),
          chatId,
        );

        if (!isSystemMessage && currentUser != null) {
          receiverId = chatData.participants.firstWhere(
            (id) => id != currentUser.uid,
            orElse: () => '',
          );

          updatedUnreadCounts = Map<String, int>.from(chatData.unreadCounts);
          if (receiverId.isNotEmpty) {
            updatedUnreadCounts[receiverId] =
                (updatedUnreadCounts[receiverId] ?? 0) + 1;
          }
        }
      }

      final senderId = isSystemMessage ? 'system' : currentUser!.uid;
      final senderName =
          isSystemMessage ? 'System' : currentUser?.displayName ?? 'Unknown';
      final senderImageUrl = isSystemMessage ? null : currentUser?.photoURL;

      final messageModel = MessageModel(
        id: messageId,
        senderId: senderId,
        senderName: senderName,
        senderImageUrl: senderImageUrl,
        receiverId: receiverId,
        message:
            message ?? (attachments.isNotEmpty ? attachments.first.name : ''),
        timestamp: now,
        type: type,
        status: isSystemMessage ? MessageStatus.sent : MessageStatus.sent,
        attachments: attachments,
        poll: poll,
        todo: todo,
        extraData: extraData ?? {},
        isSystemMessage: isSystemMessage,
        paymentRequestId: paymentRequestId,
        paymentAmount: paymentAmount,
        payToUserIds: payToUserIds,
        paymentNote: paymentNote,
        paymentUpiId: paymentUpiId,
        payToPhoneNumber: payToPhoneNumber,
        paymentStatus: paymentStatus,
        seenBy:
            isSystemMessage || currentUser == null
                ? {}
                : {currentUser.uid: now},
      );

      final messageRef = _database.ref('chats/$chatId/messages/$messageId');
      await messageRef.set(messageModel.toMap());

      if (chatData != null && currentUser != null) {
        await chatRef.update({
          'lastMessage': messageModel.previewText(),
          'lastSenderId': currentUser.uid,
          'lastMessageTime': now.millisecondsSinceEpoch,
          'lastMessageType': messageModel.type.name,
          'unreadCounts': updatedUnreadCounts,
        });
      }

      debugPrint('Message sent successfully: $messageId');
      return messageModel;
    } catch (e) {
      debugPrint('Error sending message: $e');
      rethrow;
    }
  }

  /// Get messages stream for a chat
  Stream<List<MessageModel>> getMessagesStream(String chatId) {
    return _database
        .ref('chats/$chatId/messages')
        .orderByChild('timestamp')
        .onValue
        .map((event) {
          final data = event.snapshot.value;
          if (data == null) return <MessageModel>[];

          final messagesMap = Map<String, dynamic>.from(data as Map);
          final messages =
              messagesMap.entries.map((entry) {
                final messageData = Map<String, dynamic>.from(
                  entry.value as Map,
                );
                return MessageModel.fromMap(messageData, entry.key);
              }).toList();

          // Sort by timestamp ascending (oldest first for chat display)
          messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          return messages;
        });
  }

  /// Get user's chats stream
  Stream<List<ChatModel>> getUserChatsStream() {
    final currentUser = _authService.currentUser;
    if (currentUser == null) return Stream.value([]);

    return _database.ref('chats').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return <ChatModel>[];

      final chatsMap = Map<String, dynamic>.from(data as Map);
      final chats = <ChatModel>[];

      for (final entry in chatsMap.entries) {
        final chatData = Map<String, dynamic>.from(entry.value as Map);
        final chat = ChatModel.fromMap(chatData, entry.key);

        // Only include chats where current user is a participant
        if (chat.participants.contains(currentUser.uid)) {
          chats.add(chat);
        }
      }

      // Sort by last message time descending
      chats.sort((a, b) {
        final aTime =
            a.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            b.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      return chats;
    });
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead(String chatId) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) return;

      final chatRef = _database.ref('chats/$chatId');
      await chatRef.update({'unreadCounts/${currentUser.uid}': 0});

      debugPrint('Messages marked as read for chat: $chatId');

      final messagesRef = _database.ref('chats/$chatId/messages');
      final snapshot = await messagesRef.get();
      if (snapshot.exists && snapshot.value is Map) {
        final updates = <String, Object?>{};
        final now = DateTime.now().millisecondsSinceEpoch;
        final data = Map<String, dynamic>.from(snapshot.value as Map);

        data.forEach((messageId, value) {
          final messageData = Map<String, dynamic>.from(value as Map);
          final senderId = messageData['senderId']?.toString();
          if (senderId == currentUser.uid) return;

          updates['$messageId/status'] = MessageStatus.read.name;
          updates['$messageId/seenBy/${currentUser.uid}'] = now;
        });

        if (updates.isNotEmpty) {
          await messagesRef.update(updates);
        }
      }
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  Future<void> markMessagesAsDelivered(String chatId) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) return;

      final messagesRef = _database.ref('chats/$chatId/messages');
      final snapshot = await messagesRef.get();
      if (!snapshot.exists || snapshot.value is! Map) return;

      final updates = <String, Object?>{};
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      data.forEach((messageId, value) {
        final messageData = Map<String, dynamic>.from(value as Map);
        final senderId = messageData['senderId']?.toString();
        if (senderId == currentUser.uid) return;

        final status =
            messageData['status']?.toString() ?? MessageStatus.sent.name;
        if (status == MessageStatus.sent.name) {
          updates['$messageId/status'] = MessageStatus.delivered.name;
        }
      });

      if (updates.isNotEmpty) {
        await messagesRef.update(updates);
      }
    } catch (e) {
      debugPrint('Error marking messages as delivered: $e');
    }
  }

  Future<void> editMessage({
    required String chatId,
    required String messageId,
    String? newText,
    List<MessageAttachment>? attachments,
    PollData? poll,
    TodoData? todo,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final messageRef = _database.ref('chats/$chatId/messages/$messageId');
      final snapshot = await messageRef.get();
      if (!snapshot.exists) {
        throw Exception('Message not found');
      }

      final rawData = Map<String, dynamic>.from(snapshot.value as Map);
      final existingMessage = MessageModel.fromMap(rawData, messageId);
      final now = DateTime.now();

      final history = List<MessageEditEntry>.from(existingMessage.editHistory);
      history.add(
        MessageEditEntry(text: existingMessage.message, editedAt: now),
      );
      if (history.length > 10) {
        history.removeAt(0);
      }

      final updatedAttachments = attachments ?? existingMessage.attachments;
      final updatedMessage = existingMessage.copyWith(
        message: newText ?? existingMessage.message,
        attachments: updatedAttachments,
        poll: poll ?? existingMessage.poll,
        todo: todo ?? existingMessage.todo,
        editHistory: history,
        editedAt: now,
        extraData:
            extraData != null
                ? {...existingMessage.extraData, ...extraData}
                : existingMessage.extraData,
      );

      await messageRef.update({
        'message': updatedMessage.message,
        'attachments':
            updatedAttachments.map((attachment) => attachment.toMap()).toList(),
        'poll': updatedMessage.poll?.toMap(),
        'todo': updatedMessage.todo?.toMap(),
        'editedAt': now.millisecondsSinceEpoch,
        'editHistory': history.map((entry) => entry.toMap()).toList(),
        if (extraData != null) 'extraData': updatedMessage.extraData,
      });

      final chatRef = _database.ref('chats/$chatId');
      final chatSnapshot = await chatRef.get();
      if (chatSnapshot.exists) {
        final chatData = Map<String, dynamic>.from(chatSnapshot.value as Map);
        final lastMessageTime = chatData['lastMessageTime'] as int?;
        final lastSenderId = chatData['lastSenderId']?.toString();
        if (lastMessageTime ==
                updatedMessage.timestamp.millisecondsSinceEpoch &&
            lastSenderId == updatedMessage.senderId) {
          await chatRef.update({
            'lastMessage': updatedMessage.previewText(),
            'lastMessageType': updatedMessage.type.name,
          });
        }
      }
    } catch (e) {
      debugPrint('Error editing message: $e');
      rethrow;
    }
  }

  /// Create or get a group chat
  Future<String> createOrGetGroupChat({
    required String groupId,
    required String groupName,
    required List<String> memberIds,
    required Map<String, String> memberNames,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final chatRef = _database.ref('groupChats/$groupId');
      final chatSnapshot = await chatRef.get();

      if (!chatSnapshot.exists) {
        // Create new group chat
        final chatData = {
          'id': groupId,
          'groupName': groupName,
          'members': memberIds,
          'memberNames': memberNames,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'lastMessage': 'Group created',
          'lastSenderId': 'system',
          'lastMessageTime': DateTime.now().millisecondsSinceEpoch,
          'unreadCounts': {for (String memberId in memberIds) memberId: 0},
        };

        await chatRef.set(chatData);
        debugPrint('Created new group chat: $groupId');

        // Send welcome message
        await sendGroupMessage(
          groupId: groupId,
          message: 'Welcome to $groupName! 🎉',
          isSystemMessage: true,
        );
      }

      return groupId;
    } catch (e) {
      debugPrint('Error creating/getting group chat: $e');
      rethrow;
    }
  }

  /// Send a message to group chat
  Future<MessageModel> sendGroupMessage({
    required String groupId,
    String? message,
    bool isSystemMessage = false,
    MessageType type = MessageType.text,
    List<MessageAttachment> attachments = const [],
    PollData? poll,
    TodoData? todo,
    Map<String, dynamic>? extraData,
    String? paymentRequestId,
    double? paymentAmount,
    List<String>? payToUserIds,
    String? paymentNote,
    String? paymentUpiId,
    String? payToPhoneNumber,
    Map<String, String>? paymentStatus,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null && !isSystemMessage) {
        throw Exception('User not authenticated');
      }

      final messageId =
          _database.ref('groupChats/$groupId/messages').push().key!;
      final now = DateTime.now();

      final senderId = isSystemMessage ? 'system' : currentUser!.uid;
      final senderName =
          isSystemMessage
              ? 'System'
              : (currentUser?.displayName ?? currentUser?.email ?? 'Unknown');
      final senderImageUrl = isSystemMessage ? null : currentUser?.photoURL;

      final messageModel = MessageModel(
        id: messageId,
        senderId: senderId,
        senderName: senderName,
        senderImageUrl: senderImageUrl,
        receiverId: '',
        message:
            message ?? (attachments.isNotEmpty ? attachments.first.name : ''),
        timestamp: now,
        type: type,
        status: MessageStatus.sent,
        attachments: attachments,
        poll: poll,
        todo: todo,
        extraData: extraData ?? {},
        isSystemMessage: isSystemMessage,
        paymentRequestId: paymentRequestId,
        paymentAmount: paymentAmount,
        payToUserIds: payToUserIds,
        paymentNote: paymentNote,
        paymentUpiId: paymentUpiId,
        payToPhoneNumber: payToPhoneNumber,
        paymentStatus: paymentStatus,
        seenBy:
            isSystemMessage || currentUser == null
                ? {}
                : {currentUser.uid: now},
      );

      final messageRef = _database.ref(
        'groupChats/$groupId/messages/$messageId',
      );
      await messageRef.set({...messageModel.toMap(), 'id': messageId});

      if (!isSystemMessage && currentUser != null) {
        final chatRef = _database.ref('groupChats/$groupId');
        final chatSnapshot = await chatRef.get();

        if (chatSnapshot.exists) {
          final chatData = Map<String, dynamic>.from(chatSnapshot.value as Map);
          final members = List<String>.from(chatData['members'] ?? []);
          final unreadCounts = Map<String, int>.from(
            Map<String, dynamic>.from(
              chatData['unreadCounts'] ?? {},
            ).map((key, value) => MapEntry(key, (value as num).toInt())),
          );

          for (final memberId in members) {
            if (memberId != currentUser.uid) {
              unreadCounts[memberId] = (unreadCounts[memberId] ?? 0) + 1;
            }
          }

          await chatRef.update({
            'lastMessage': messageModel.previewText(),
            'lastSenderId': currentUser.uid,
            'lastMessageTime': now.millisecondsSinceEpoch,
            'lastMessageType': messageModel.type.name,
            'unreadCounts': unreadCounts,
          });
        }
      }

      debugPrint('Group message sent successfully: $messageId');
      return messageModel;
    } catch (e) {
      debugPrint('Error sending group message: $e');
      rethrow;
    }
  }

  /// Get group messages stream
  Stream<List<MessageModel>> getGroupMessagesStream(String groupId) {
    return _database
        .ref('groupChats/$groupId/messages')
        .orderByChild('timestamp')
        .onValue
        .map((event) {
          final data = event.snapshot.value;
          if (data == null) return <MessageModel>[];

          final messagesMap = Map<String, dynamic>.from(data as Map);
          final messages =
              messagesMap.entries.map((entry) {
                final messageData = Map<String, dynamic>.from(
                  entry.value as Map,
                );
                return MessageModel.fromMap(messageData, entry.key);
              }).toList();

          messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          return messages;
        });
  }

  /// Mark group messages as read
  Future<void> markGroupMessagesAsRead(String groupId) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) return;

      final chatRef = _database.ref('groupChats/$groupId');
      await chatRef.update({'unreadCounts/${currentUser.uid}': 0});

      debugPrint('Group messages marked as read for chat: $groupId');

      final messagesRef = _database.ref('groupChats/$groupId/messages');
      final snapshot = await messagesRef.get();
      if (snapshot.exists && snapshot.value is Map) {
        final updates = <String, Object?>{};
        final now = DateTime.now().millisecondsSinceEpoch;
        final data = Map<String, dynamic>.from(snapshot.value as Map);

        data.forEach((messageId, value) {
          final messageData = Map<String, dynamic>.from(value as Map);
          final senderId = messageData['senderId']?.toString();
          if (senderId == currentUser.uid) return;

          updates['$messageId/seenBy/${currentUser.uid}'] = now;
        });

        if (updates.isNotEmpty) {
          await messagesRef.update(updates);
        }
      }
    } catch (e) {
      debugPrint('Error marking group messages as read: $e');
    }
  }

  Future<void> editGroupMessage({
    required String groupId,
    required String messageId,
    String? newText,
    List<MessageAttachment>? attachments,
    PollData? poll,
    TodoData? todo,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final messageRef = _database.ref(
        'groupChats/$groupId/messages/$messageId',
      );
      final snapshot = await messageRef.get();
      if (!snapshot.exists) {
        throw Exception('Message not found');
      }

      final rawData = Map<String, dynamic>.from(snapshot.value as Map);
      final existingMessage = MessageModel.fromMap(rawData, messageId);
      final now = DateTime.now();

      final history = List<MessageEditEntry>.from(existingMessage.editHistory);
      history.add(
        MessageEditEntry(text: existingMessage.message, editedAt: now),
      );
      if (history.length > 10) {
        history.removeAt(0);
      }

      final updatedAttachments = attachments ?? existingMessage.attachments;
      final updatedMessage = existingMessage.copyWith(
        message: newText ?? existingMessage.message,
        attachments: updatedAttachments,
        poll: poll ?? existingMessage.poll,
        todo: todo ?? existingMessage.todo,
        editHistory: history,
        editedAt: now,
        extraData:
            extraData != null
                ? {...existingMessage.extraData, ...extraData}
                : existingMessage.extraData,
      );

      await messageRef.update({
        'message': updatedMessage.message,
        'attachments':
            updatedAttachments.map((attachment) => attachment.toMap()).toList(),
        'poll': updatedMessage.poll?.toMap(),
        'todo': updatedMessage.todo?.toMap(),
        'editedAt': now.millisecondsSinceEpoch,
        'editHistory': history.map((entry) => entry.toMap()).toList(),
        if (extraData != null) 'extraData': updatedMessage.extraData,
      });

      final chatRef = _database.ref('groupChats/$groupId');
      final chatSnapshot = await chatRef.get();
      if (chatSnapshot.exists) {
        final chatData = Map<String, dynamic>.from(chatSnapshot.value as Map);
        final lastMessageTime = chatData['lastMessageTime'] as int?;
        final lastSenderId = chatData['lastSenderId']?.toString();
        if (lastMessageTime ==
                updatedMessage.timestamp.millisecondsSinceEpoch &&
            lastSenderId == updatedMessage.senderId) {
          await chatRef.update({
            'lastMessage': updatedMessage.previewText(),
            'lastMessageType': updatedMessage.type.name,
          });
        }
      }
    } catch (e) {
      debugPrint('Error editing group message: $e');
      rethrow;
    }
  }

  Future<void> togglePollVote({
    required String containerId,
    required String messageId,
    required String optionId,
    required bool isGroup,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) return;

      final basePath =
          isGroup
              ? 'groupChats/$containerId/messages'
              : 'chats/$containerId/messages';
      final messageRef = _database.ref('$basePath/$messageId');
      final snapshot = await messageRef.get();
      if (!snapshot.exists) {
        throw Exception('Poll message not found');
      }

      final rawData = Map<String, dynamic>.from(snapshot.value as Map);
      final message = MessageModel.fromMap(rawData, messageId);
      final poll = message.poll;
      if (poll == null) {
        throw Exception('Message does not contain poll');
      }

      final updatedOptions = <PollOption>[];
      bool changed = false;

      for (final option in poll.options) {
        final votes = Set<String>.of(option.votes);

        if (!poll.allowMultiple) {
          votes.remove(currentUser.uid);
        }

        if (option.id == optionId) {
          if (votes.contains(currentUser.uid)) {
            votes.remove(currentUser.uid);
          } else {
            votes.add(currentUser.uid);
          }
        }

        if (!changed && !setEquals(votes, option.votes)) {
          changed = true;
        }

        updatedOptions.add(option.copyWith(votes: votes));
      }

      if (!changed) return;

      final updatedPoll = PollData(
        question: poll.question,
        options: updatedOptions,
        allowMultiple: poll.allowMultiple,
        createdAt: poll.createdAt,
      );

      await messageRef.update({'poll': updatedPoll.toMap()});
    } catch (e) {
      debugPrint('Error toggling poll vote: $e');
      rethrow;
    }
  }

  Future<void> updateTodoItem({
    required String containerId,
    required String messageId,
    required String itemId,
    required bool isGroup,
    bool? isDone,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) return;

      final basePath =
          isGroup
              ? 'groupChats/$containerId/messages'
              : 'chats/$containerId/messages';
      final messageRef = _database.ref('$basePath/$messageId');
      final snapshot = await messageRef.get();
      if (!snapshot.exists) {
        throw Exception('To-do message not found');
      }

      final rawData = Map<String, dynamic>.from(snapshot.value as Map);
      final message = MessageModel.fromMap(rawData, messageId);
      final todo = message.todo;
      if (todo == null) {
        throw Exception('Message does not contain a to-do list');
      }

      final updatedItems = <TodoItem>[];
      bool changed = false;
      final now = DateTime.now();

      for (final item in todo.items) {
        if (item.id != itemId) {
          updatedItems.add(item);
          continue;
        }

        final newStatus = isDone ?? !item.isDone;
        final updatedItem = item.copyWith(
          isDone: newStatus,
          completedAt: newStatus ? now : null,
          completedBy: newStatus ? currentUser.uid : null,
        );

        if (!changed &&
            (item.isDone != updatedItem.isDone ||
                item.completedAt != updatedItem.completedAt)) {
          changed = true;
        }

        updatedItems.add(updatedItem);
      }

      if (!changed) return;

      final updatedTodo = TodoData(title: todo.title, items: updatedItems);
      await messageRef.update({'todo': updatedTodo.toMap()});
    } catch (e) {
      debugPrint('Error updating todo item: $e');
      rethrow;
    }
  }

  /// Search for users to start a chat with
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) return [];

      final usersQuery =
          await _firestore
              .collection('users')
              .where('username', isGreaterThanOrEqualTo: query)
              .where('username', isLessThanOrEqualTo: '$query\uf8ff')
              .limit(20)
              .get();

      return usersQuery.docs
          .where((doc) => doc.id != currentUser.uid) // Exclude current user
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
    } catch (e) {
      debugPrint('Error searching users: $e');
      return [];
    }
  }

  /// Update payment status for a specific user in a payment request message
  Future<void> updateMessagePaymentStatus({
    required String chatId,
    required String messageId,
    required String userId,
    required String status, // "PAID" or "PENDING"
    required bool isGroupChat,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final path = isGroupChat
          ? 'groupChats/$chatId/messages/$messageId'
          : 'chats/$chatId/messages/$messageId';

      final messageRef = _database.ref(path);
      final snapshot = await messageRef.get();
      
      if (!snapshot.exists) {
        throw Exception('Message not found');
      }

      final rawData = Map<String, dynamic>.from(snapshot.value as Map);
      final paymentStatus = Map<String, String>.from(
        rawData['paymentStatus'] as Map? ?? {},
      );

      // Update status for this user
      paymentStatus[userId] = status;

      // Check if all users have paid
      final allPaid = _checkAllUsersPaid(paymentStatus);

      // Update both status and completion flag
      final updates = <String, dynamic>{
        'paymentStatus': paymentStatus,
        'isPaymentCompleted': allPaid,
      };

      await messageRef.update(updates);

      if (allPaid) {
        debugPrint('🎉 Payment request completed! All users paid.');
      } else {
        debugPrint('✅ Updated payment status: $userId -> $status');
      }
    } catch (e) {
      debugPrint('❌ Error updating payment status: $e');
      rethrow;
    }
  }

  /// Check if all users in the payment request have paid
  bool _checkAllUsersPaid(Map<String, String> paymentStatus) {
    if (paymentStatus.isEmpty) return false;
    
    for (final status in paymentStatus.values) {
      if (status != 'PAID') {
        return false;
      }
    }
    
    return true;
  }
}

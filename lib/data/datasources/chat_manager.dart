import 'package:roomie/data/models/base_chat.dart';
import 'package:roomie/data/datasources/chat_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ChatManager class that implements OOP principles for managing different chat types
/// This provides a unified interface for all chat operations
class ChatManager {
  final ChatService _chatService = ChatService();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  /// Factory method to create appropriate chat type
  static BaseChat createChat({
    required String type,
    required Map<String, dynamic> data,
    required String id,
  }) {
    switch (type.toLowerCase()) {
      case 'individual':
        return IndividualChat.fromMap(data, id);
      case 'group':
        return GroupChat.fromMap(data, id);
      default:
        throw ArgumentError('Unknown chat type: $type');
    }
  }

  /// Create or get individual chat
  Future<IndividualChat> createOrGetIndividualChat({
    required String otherUserId,
    required String otherUserName,
    String? otherUserImageUrl,
  }) async {
    try {
      final chatId = await _chatService.createOrGetChat(
        otherUserId: otherUserId,
        otherUserName: otherUserName,
        otherUserImageUrl: otherUserImageUrl,
      );

      return IndividualChat(
        id: chatId,
        createdAt: DateTime.now(),
        otherUserId: otherUserId,
        otherUserName: otherUserName,
        otherUserImageUrl: otherUserImageUrl,
        unreadCounts: {_currentUserId: 0, otherUserId: 0},
      );
    } catch (e) {
      throw Exception('Failed to create individual chat: $e');
    }
  }

  /// Create group chat (placeholder - implement when needed)
  Future<GroupChat> createGroupChat({
    required String groupName,
    required List<String> participantIds,
    required Map<String, String> participantNames,
    String? groupImageUrl,
  }) async {
    try {
      // For now, generate a simple group chat ID
      final chatId = 'group_${DateTime.now().millisecondsSinceEpoch}';

      final unreadCounts = Map<String, int>.fromEntries(
        participantIds.map((id) => MapEntry(id, 0)),
      );

      return GroupChat(
        id: chatId,
        createdAt: DateTime.now(),
        groupName: groupName,
        groupImageUrl: groupImageUrl,
        participants: participantIds,
        participantNames: participantNames,
        unreadCounts: unreadCounts,
        adminId: _currentUserId,
      );
    } catch (e) {
      throw Exception('Failed to create group chat: $e');
    }
  }

  /// Get all chats for current user
  Future<List<BaseChat>> getAllChats() async {
    try {
      final chatsList = <BaseChat>[];

      // Get individual chats
      final individualChats = await _getIndividualChats();
      chatsList.addAll(individualChats);

      // Get group chats
      final groupChats = await _getGroupChats();
      chatsList.addAll(groupChats);

      // Sort by last message time
      chatsList.sort((a, b) {
        if (a.lastMessageTime == null && b.lastMessageTime == null) return 0;
        if (a.lastMessageTime == null) return 1;
        if (b.lastMessageTime == null) return -1;
        return b.lastMessageTime!.compareTo(a.lastMessageTime!);
      });

      return chatsList;
    } catch (e) {
      throw Exception('Failed to get chats: $e');
    }
  }

  /// Private method to get individual chats
  Future<List<IndividualChat>> _getIndividualChats() async {
    // Implementation to fetch individual chats from database
    // This would use your existing chat service methods
    return [];
  }

  /// Private method to get group chats
  Future<List<GroupChat>> _getGroupChats() async {
    // Implementation to fetch group chats from database
    // This would use your existing chat service methods
    return [];
  }

  /// Send message to any chat type
  Future<void> sendMessage({
    required BaseChat chat,
    required String message,
  }) async {
    try {
      await _chatService.sendMessage(chatId: chat.id, message: message);
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  /// Mark messages as read
  Future<void> markAsRead(BaseChat chat) async {
    try {
      await _chatService.markMessagesAsRead(chat.id);
    } catch (e) {
      throw Exception('Failed to mark as read: $e');
    }
  }

  /// Get unread count for all chats
  Future<int> getTotalUnreadCount() async {
    try {
      final chats = await getAllChats();
      return chats.fold<int>(
        0,
        (total, chat) => total + chat.getUnreadCount(_currentUserId),
      );
    } catch (e) {
      return 0;
    }
  }

  /// Delete chat
  Future<void> deleteChat(BaseChat chat) async {
    try {
      // Implementation depends on your chat service
      // await _chatService.deleteChat(chat.id);
    } catch (e) {
      throw Exception('Failed to delete chat: $e');
    }
  }

  /// Search chats
  List<BaseChat> searchChats(List<BaseChat> chats, String query) {
    if (query.isEmpty) return chats;

    return chats.where((chat) {
      return chat.getChatTitle().toLowerCase().contains(query.toLowerCase());
    }).toList();
  }
}

/// Utility class for chat-related operations
class ChatUtils {
  /// Generate chat ID for individual chat
  static String generateIndividualChatId(String userId1, String userId2) {
    final participants = [userId1, userId2]..sort();
    return '${participants[0]}_${participants[1]}';
  }

  /// Generate chat ID for group chat
  static String generateGroupChatId() {
    return 'group_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Format chat time
  static String formatChatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  /// Validate message content
  static bool isValidMessage(String message) {
    return message.trim().isNotEmpty && message.length <= 1000;
  }

  /// Get chat preview text
  static String getChatPreview(
    String? lastMessage,
    String? lastSenderId,
    String currentUserId,
  ) {
    if (lastMessage == null || lastMessage.isEmpty) {
      return 'No messages yet';
    }

    final isFromCurrentUser = lastSenderId == currentUserId;
    final prefix = isFromCurrentUser ? 'You: ' : '';

    if (lastMessage.length > 50) {
      return '$prefix${lastMessage.substring(0, 50)}...';
    }

    return '$prefix$lastMessage';
  }
}

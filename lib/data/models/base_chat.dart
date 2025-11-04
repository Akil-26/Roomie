/// Base class for all chat-related functionality
/// This implements OOP principles for better code organization and reusability
abstract class BaseChat {
  final String id;
  final DateTime createdAt;
  final DateTime? lastMessageTime;
  final String? lastMessage;
  final String? lastSenderId;

  BaseChat({
    required this.id,
    required this.createdAt,
    this.lastMessageTime,
    this.lastMessage,
    this.lastSenderId,
  });

  /// Abstract method to be implemented by subclasses
  String getChatTitle();

  /// Abstract method to get chat participants
  List<String> getParticipants();

  /// Abstract method to get chat image URL
  String? getChatImageUrl();

  /// Common method for all chat types
  bool hasUnreadMessages(String userId) {
    return getUnreadCount(userId) > 0;
  }

  /// Abstract method to get unread count for a specific user
  int getUnreadCount(String userId);

  /// Convert to map for database operations
  Map<String, dynamic> toMap();

  /// Common utility method
  String getTimeAgo() {
    if (lastMessageTime == null) return 'No messages';

    final now = DateTime.now();
    final difference = now.difference(lastMessageTime!);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

/// Individual chat implementation
class IndividualChat extends BaseChat {
  final String otherUserId;
  final String otherUserName;
  final String? otherUserImageUrl;
  final Map<String, int> unreadCounts;

  IndividualChat({
    required super.id,
    required super.createdAt,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserImageUrl,
    required this.unreadCounts,
    super.lastMessageTime,
    super.lastMessage,
    super.lastSenderId,
  });

  @override
  String getChatTitle() => otherUserName;

  @override
  List<String> getParticipants() => [otherUserId];

  @override
  String? getChatImageUrl() => otherUserImageUrl;

  @override
  int getUnreadCount(String userId) => unreadCounts[userId] ?? 0;

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'otherUserId': otherUserId,
      'otherUserName': otherUserName,
      'otherUserImageUrl': otherUserImageUrl,
      'unreadCounts': unreadCounts,
      'lastMessageTime': lastMessageTime?.millisecondsSinceEpoch,
      'lastMessage': lastMessage,
      'lastSenderId': lastSenderId,
      'isGroup': false,
    };
  }

  factory IndividualChat.fromMap(Map<String, dynamic> map, String id) {
    return IndividualChat(
      id: id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      otherUserId: map['otherUserId'],
      otherUserName: map['otherUserName'],
      otherUserImageUrl: map['otherUserImageUrl'],
      unreadCounts: Map<String, int>.from(map['unreadCounts'] ?? {}),
      lastMessageTime:
          map['lastMessageTime'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['lastMessageTime'])
              : null,
      lastMessage: map['lastMessage'],
      lastSenderId: map['lastSenderId'],
    );
  }
}

/// Group chat implementation
class GroupChat extends BaseChat {
  final String groupName;
  final String? groupImageUrl;
  final List<String> participants;
  final Map<String, String> participantNames;
  final Map<String, int> unreadCounts;
  final String adminId;

  GroupChat({
    required super.id,
    required super.createdAt,
    required this.groupName,
    this.groupImageUrl,
    required this.participants,
    required this.participantNames,
    required this.unreadCounts,
    required this.adminId,
    super.lastMessageTime,
    super.lastMessage,
    super.lastSenderId,
  });

  @override
  String getChatTitle() => groupName;

  @override
  List<String> getParticipants() => participants;

  @override
  String? getChatImageUrl() => groupImageUrl;

  @override
  int getUnreadCount(String userId) => unreadCounts[userId] ?? 0;

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'groupName': groupName,
      'groupImageUrl': groupImageUrl,
      'participants': participants,
      'participantNames': participantNames,
      'unreadCounts': unreadCounts,
      'adminId': adminId,
      'lastMessageTime': lastMessageTime?.millisecondsSinceEpoch,
      'lastMessage': lastMessage,
      'lastSenderId': lastSenderId,
      'isGroup': true,
    };
  }

  factory GroupChat.fromMap(Map<String, dynamic> map, String id) {
    return GroupChat(
      id: id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      groupName: map['groupName'],
      groupImageUrl: map['groupImageUrl'],
      participants: List<String>.from(map['participants'] ?? []),
      participantNames: Map<String, String>.from(map['participantNames'] ?? {}),
      unreadCounts: Map<String, int>.from(map['unreadCounts'] ?? {}),
      adminId: map['adminId'],
      lastMessageTime:
          map['lastMessageTime'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['lastMessageTime'])
              : null,
      lastMessage: map['lastMessage'],
      lastSenderId: map['lastSenderId'],
    );
  }

  /// Group-specific methods
  bool isAdmin(String userId) => adminId == userId;

  bool isMember(String userId) => participants.contains(userId);

  int get memberCount => participants.length;
}

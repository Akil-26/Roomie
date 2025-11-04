class ChatModel {
  final String id;
  final List<String> participants;
  final Map<String, String> participantNames;
  final Map<String, String?> participantImages;
  final String? lastMessage;
  final String? lastSenderId;
  final DateTime? lastMessageTime;
  final Map<String, int> unreadCounts;
  final bool isGroup;
  final String? groupName;
  final String? groupImageUrl;

  ChatModel({
    required this.id,
    required this.participants,
    required this.participantNames,
    required this.participantImages,
    this.lastMessage,
    this.lastSenderId,
    this.lastMessageTime,
    required this.unreadCounts,
    this.isGroup = false,
    this.groupName,
    this.groupImageUrl,
  });

  factory ChatModel.fromMap(Map<String, dynamic> map, String id) {
    return ChatModel(
      id: id,
      participants: List<String>.from(map['participants'] ?? []),
      participantNames: Map<String, String>.from(map['participantNames'] ?? {}),
      participantImages: Map<String, String?>.from(
        map['participantImages'] ?? {},
      ),
      lastMessage: map['lastMessage'],
      lastSenderId: map['lastSenderId'],
      lastMessageTime:
          map['lastMessageTime'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['lastMessageTime'])
              : null,
      unreadCounts: Map<String, int>.from(map['unreadCounts'] ?? {}),
      isGroup: map['isGroup'] ?? false,
      groupName: map['groupName'],
      groupImageUrl: map['groupImageUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'participants': participants,
      'participantNames': participantNames,
      'participantImages': participantImages,
      'lastMessage': lastMessage,
      'lastSenderId': lastSenderId,
      'lastMessageTime': lastMessageTime?.millisecondsSinceEpoch,
      'unreadCounts': unreadCounts,
      'isGroup': isGroup,
      'groupName': groupName,
      'groupImageUrl': groupImageUrl,
    };
  }

  String getOtherParticipantName(String currentUserId) {
    if (isGroup) return groupName ?? 'Group Chat';

    final otherParticipant = participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );
    return participantNames[otherParticipant] ?? 'Unknown User';
  }

  String? getOtherParticipantImage(String currentUserId) {
    if (isGroup) return groupImageUrl;

    final otherParticipant = participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );
    return participantImages[otherParticipant];
  }

  int getUnreadCount(String userId) {
    return unreadCounts[userId] ?? 0;
  }
}

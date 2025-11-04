/// Message Entity
/// Represents a message in the domain layer
class MessageEntity {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final MessageType type;
  final String? imageUrl;
  final String? replyToId;
  final MessageStatus status;

  const MessageEntity({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    this.type = MessageType.text,
    this.imageUrl,
    this.replyToId,
    this.status = MessageStatus.sent,
  });

  MessageEntity copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? content,
    DateTime? timestamp,
    MessageType? type,
    String? imageUrl,
    String? replyToId,
    MessageStatus? status,
  }) {
    return MessageEntity(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      imageUrl: imageUrl ?? this.imageUrl,
      replyToId: replyToId ?? this.replyToId,
      status: status ?? this.status,
    );
  }

  bool get isText => type == MessageType.text;
  bool get isImage => type == MessageType.image;
  bool get hasReply => replyToId != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'MessageEntity(id: $id, sender: $senderName, type: $type)';
}

/// Message Types
enum MessageType { text, image, system }

/// Message Status
enum MessageStatus { sending, sent, delivered, read, failed }

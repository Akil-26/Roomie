import 'package:collection/collection.dart';

// Helper functions for safe type casting from Firebase
Map<String, dynamic> _safeCastMap(dynamic value) {
  if (value == null) return {};
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return Map<String, dynamic>.from(
      value.map((key, val) => MapEntry(key.toString(), val)),
    );
  }
  return {};
}

List<dynamic> _safeListFromMap(dynamic value) {
  if (value == null) return [];
  if (value is List) return value;
  return [];
}

enum MessageType { text, image, file, audio, voice, poll, todo, system }

enum MessageStatus { sending, sent, delivered, read }

enum AttachmentType { image, audio, voice, document, video, other }

class MessageAttachment {
  final String url;
  final String name;
  final AttachmentType type;
  final String? mimeType;
  final int? size;
  final int? durationInMs;
  final String? thumbnailUrl;

  const MessageAttachment({
    required this.url,
    required this.name,
    required this.type,
    this.mimeType,
    this.size,
    this.durationInMs,
    this.thumbnailUrl,
  });

  factory MessageAttachment.fromMap(Map<String, dynamic> map) {
    final typeString = (map['type'] ?? '').toString();
    final attachmentType =
        AttachmentType.values.firstWhereOrNull(
          (value) => value.name == typeString,
        ) ??
        AttachmentType.other;

    return MessageAttachment(
      url: map['url'] ?? '',
      name: map['name'] ?? 'file',
      type: attachmentType,
      mimeType: map['mimeType']?.toString(),
      size: map['size'] is int ? map['size'] as int : null,
      durationInMs:
          map['durationInMs'] is int ? map['durationInMs'] as int : null,
      thumbnailUrl: map['thumbnailUrl']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'name': name,
      'type': type.name,
      if (mimeType != null) 'mimeType': mimeType,
      if (size != null) 'size': size,
      if (durationInMs != null) 'durationInMs': durationInMs,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
    };
  }
}

class MessageEditEntry {
  final String text;
  final DateTime editedAt;

  const MessageEditEntry({required this.text, required this.editedAt});

  factory MessageEditEntry.fromMap(Map<String, dynamic> map) {
    final timestamp = map['editedAt'];
    return MessageEditEntry(
      text: map['text']?.toString() ?? '',
      editedAt:
          timestamp is int
              ? DateTime.fromMillisecondsSinceEpoch(timestamp)
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'text': text, 'editedAt': editedAt.millisecondsSinceEpoch};
  }
}

class PollOption {
  final String id;
  final String title;
  final Set<String> votes;

  const PollOption({
    required this.id,
    required this.title,
    this.votes = const {},
  });

  factory PollOption.fromMap(Map<String, dynamic> map) {
    final votesData = map['votes'];
    final votesList =
        votesData is List
            ? votesData.map((e) => e.toString()).toList()
            : <String>[];

    return PollOption(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      votes: Set<String>.from(votesList),
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'title': title, 'votes': votes.toList()};
  }

  PollOption copyWith({String? id, String? title, Set<String>? votes}) {
    return PollOption(
      id: id ?? this.id,
      title: title ?? this.title,
      votes: votes ?? this.votes,
    );
  }
}

class PollData {
  final String question;
  final List<PollOption> options;
  final bool allowMultiple;
  final DateTime createdAt;

  const PollData({
    required this.question,
    required this.options,
    this.allowMultiple = false,
    required this.createdAt,
  });

  factory PollData.fromMap(Map<String, dynamic> map) {
    final optionsData = _safeListFromMap(map['options']);
    return PollData(
      question: map['question']?.toString() ?? '',
      options:
          optionsData
              .map((item) => PollOption.fromMap(_safeCastMap(item)))
              .toList(),
      allowMultiple: map['allowMultiple'] == true,
      createdAt:
          map['createdAt'] is int
              ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'question': question,
      'options': options.map((option) => option.toMap()).toList(),
      'allowMultiple': allowMultiple,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }
}

class TodoItem {
  final String id;
  final String title;
  final bool isDone;
  final String? assignedTo;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final String? completedBy;

  const TodoItem({
    required this.id,
    required this.title,
    this.isDone = false,
    this.assignedTo,
    this.dueDate,
    this.completedAt,
    this.completedBy,
  });

  factory TodoItem.fromMap(Map<String, dynamic> map) {
    return TodoItem(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      isDone: map['isDone'] == true,
      assignedTo: map['assignedTo']?.toString(),
      dueDate:
          map['dueDate'] is int
              ? DateTime.fromMillisecondsSinceEpoch(map['dueDate'] as int)
              : null,
      completedAt:
          map['completedAt'] is int
              ? DateTime.fromMillisecondsSinceEpoch(map['completedAt'] as int)
              : null,
      completedBy: map['completedBy']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'isDone': isDone,
      if (assignedTo != null) 'assignedTo': assignedTo,
      if (dueDate != null) 'dueDate': dueDate!.millisecondsSinceEpoch,
      if (completedAt != null)
        'completedAt': completedAt!.millisecondsSinceEpoch,
      if (completedBy != null) 'completedBy': completedBy,
    };
  }

  TodoItem copyWith({
    String? id,
    String? title,
    bool? isDone,
    String? assignedTo,
    DateTime? dueDate,
    DateTime? completedAt,
    String? completedBy,
  }) {
    return TodoItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
      assignedTo: assignedTo ?? this.assignedTo,
      dueDate: dueDate ?? this.dueDate,
      completedAt: completedAt ?? this.completedAt,
      completedBy: completedBy ?? this.completedBy,
    );
  }
}

class TodoData {
  final String title;
  final List<TodoItem> items;

  const TodoData({required this.title, required this.items});

  factory TodoData.fromMap(Map<String, dynamic> map) {
    final itemsData = _safeListFromMap(map['items']);
    return TodoData(
      title: map['title']?.toString() ?? '',
      items:
          itemsData
              .map((item) => TodoItem.fromMap(_safeCastMap(item)))
              .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'items': items.map((item) => item.toMap()).toList(),
    };
  }
}

class MessageModel {
  final String id;
  final String senderId;
  final String senderName;
  final String? senderImageUrl;
  final String receiverId;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final MessageType type;
  final MessageStatus status;
  final Map<String, DateTime> seenBy;
  final DateTime? editedAt;
  final List<MessageEditEntry> editHistory;
  final List<MessageAttachment> attachments;
  final PollData? poll;
  final TodoData? todo;
  final Map<String, dynamic> extraData;
  final bool isSystemMessage;

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderImageUrl,
    required this.receiverId,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.type = MessageType.text,
    this.status = MessageStatus.sent,
    this.seenBy = const {},
    this.editedAt,
    this.editHistory = const [],
    this.attachments = const [],
    this.poll,
    this.todo,
    this.extraData = const {},
    this.isSystemMessage = false,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map, String id) {
    final typeString = map['type']?.toString() ?? MessageType.text.name;
    final statusString = map['status']?.toString() ?? MessageStatus.sent.name;

    final seenByMap = <String, DateTime>{};
    if (map['seenBy'] is Map) {
      (map['seenBy'] as Map).forEach((key, value) {
        if (value is int) {
          seenByMap[key.toString()] = DateTime.fromMillisecondsSinceEpoch(
            value,
          );
        }
      });
    }

    return MessageModel(
      id: id,
      senderId: map['senderId']?.toString() ?? '',
      senderName: map['senderName']?.toString() ?? '',
      senderImageUrl: map['senderImageUrl']?.toString(),
      receiverId: map['receiverId']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      timestamp:
          map['timestamp'] is int
              ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
              : DateTime.now(),
      isRead: map['isRead'] == true,
      type:
          MessageType.values.firstWhereOrNull(
            (value) => value.name == typeString,
          ) ??
          MessageType.text,
      status:
          MessageStatus.values.firstWhereOrNull(
            (value) => value.name == statusString,
          ) ??
          MessageStatus.sent,
      seenBy: seenByMap,
      editedAt:
          map['editedAt'] is int
              ? DateTime.fromMillisecondsSinceEpoch(map['editedAt'] as int)
              : null,
      editHistory:
          _safeListFromMap(map['editHistory'])
              .map((item) => MessageEditEntry.fromMap(_safeCastMap(item)))
              .toList(),
      attachments:
          _safeListFromMap(map['attachments'])
              .map((item) => MessageAttachment.fromMap(_safeCastMap(item)))
              .toList(),
      poll:
          map['poll'] != null
              ? PollData.fromMap(_safeCastMap(map['poll']))
              : null,
      todo:
          map['todo'] != null
              ? TodoData.fromMap(_safeCastMap(map['todo']))
              : null,
      extraData: _safeCastMap(map['extraData'] ?? const {}),
      isSystemMessage:
          map['isSystemMessage'] == true ||
          typeString == MessageType.system.name,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderImageUrl': senderImageUrl,
      'receiverId': receiverId,
      'message': message,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isRead': isRead,
      'type': type.name,
      'status': status.name,
      if (seenBy.isNotEmpty)
        'seenBy': seenBy.map(
          (key, value) => MapEntry(key, value.millisecondsSinceEpoch),
        ),
      if (editedAt != null) 'editedAt': editedAt!.millisecondsSinceEpoch,
      if (editHistory.isNotEmpty)
        'editHistory': editHistory.map((entry) => entry.toMap()).toList(),
      if (attachments.isNotEmpty)
        'attachments':
            attachments.map((attachment) => attachment.toMap()).toList(),
      if (poll != null) 'poll': poll!.toMap(),
      if (todo != null) 'todo': todo!.toMap(),
      if (extraData.isNotEmpty) 'extraData': extraData,
      'isSystemMessage': isSystemMessage,
    };
  }

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? senderImageUrl,
    String? receiverId,
    String? message,
    DateTime? timestamp,
    bool? isRead,
    MessageType? type,
    MessageStatus? status,
    Map<String, DateTime>? seenBy,
    DateTime? editedAt,
    List<MessageEditEntry>? editHistory,
    List<MessageAttachment>? attachments,
    PollData? poll,
    TodoData? todo,
    Map<String, dynamic>? extraData,
    bool? isSystemMessage,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderImageUrl: senderImageUrl ?? this.senderImageUrl,
      receiverId: receiverId ?? this.receiverId,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      type: type ?? this.type,
      status: status ?? this.status,
      seenBy: seenBy ?? this.seenBy,
      editedAt: editedAt ?? this.editedAt,
      editHistory: editHistory ?? this.editHistory,
      attachments: attachments ?? this.attachments,
      poll: poll ?? this.poll,
      todo: todo ?? this.todo,
      extraData: extraData ?? this.extraData,
      isSystemMessage: isSystemMessage ?? this.isSystemMessage,
    );
  }

  String previewText({String? currentUserId}) {
    switch (type) {
      case MessageType.image:
        return attachments.isNotEmpty ? '[Image]' : 'Image';
      case MessageType.file:
        return attachments.isNotEmpty
            ? '[File] ${attachments.first.name}'
            : 'File shared';
      case MessageType.audio:
      case MessageType.voice:
        return 'Voice message';
      case MessageType.poll:
        return poll != null ? 'Poll: ${poll!.question}' : 'Poll';
      case MessageType.todo:
        return todo != null ? 'To-do: ${todo!.title}' : 'To-do list';
      case MessageType.system:
        return message;
      case MessageType.text:
        return message.isEmpty ? 'Message' : message;
    }
  }
}

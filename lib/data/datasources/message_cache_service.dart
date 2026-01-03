import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:roomie/data/models/message_model.dart';

/// Service for caching messages locally using Hive
/// This enables offline access and faster loading of messages
class MessageCacheService {
  static final MessageCacheService _instance = MessageCacheService._internal();
  factory MessageCacheService() => _instance;
  MessageCacheService._internal();

  static const String _messagesBoxPrefix = 'messages_';
  static const String _metadataBox = 'cache_metadata';
  static const int _maxMessagesPerChat = 100; // Keep last 100 messages per chat

  bool _initialized = false;

  /// Initialize Hive for message caching
  Future<void> init() async {
    if (_initialized) return;

    try {
      await Hive.initFlutter();
      await Hive.openBox<Map>(_metadataBox);
      _initialized = true;
      debugPrint('MessageCacheService initialized');
    } catch (e) {
      debugPrint('Error initializing MessageCacheService: $e');
    }
  }

  /// Get the box name for a specific chat
  String _getBoxName(String chatId) => '$_messagesBoxPrefix$chatId';

  /// Open or get the message box for a chat
  Future<Box<Map>?> _getMessageBox(String chatId) async {
    try {
      final boxName = _getBoxName(chatId);
      if (Hive.isBoxOpen(boxName)) {
        return Hive.box<Map>(boxName);
      }
      return await Hive.openBox<Map>(boxName);
    } catch (e) {
      debugPrint('Error opening message box for $chatId: $e');
      return null;
    }
  }

  /// Cache a single message
  Future<void> cacheMessage(String chatId, MessageModel message) async {
    try {
      final box = await _getMessageBox(chatId);
      if (box == null) return;

      await box.put(message.id, message.toMap());
      
      // Cleanup old messages if too many
      await _cleanupOldMessages(box);
    } catch (e) {
      debugPrint('Error caching message: $e');
    }
  }

  /// Cache multiple messages at once
  Future<void> cacheMessages(String chatId, List<MessageModel> messages) async {
    try {
      final box = await _getMessageBox(chatId);
      if (box == null) return;

      final entries = <String, Map>{};
      for (final msg in messages) {
        entries[msg.id] = msg.toMap();
      }

      await box.putAll(entries);
      
      // Cleanup old messages if too many
      await _cleanupOldMessages(box);
      
      // Update last sync time
      await _updateLastSync(chatId);
    } catch (e) {
      debugPrint('Error caching messages: $e');
    }
  }

  /// Get cached messages for a chat
  Future<List<MessageModel>> getCachedMessages(String chatId) async {
    try {
      final box = await _getMessageBox(chatId);
      if (box == null) return [];

      final messages = <MessageModel>[];
      for (final key in box.keys) {
        try {
          final data = box.get(key);
          if (data != null) {
            final mapData = Map<String, dynamic>.from(data);
            messages.add(MessageModel.fromMap(mapData, key.toString()));
          }
        } catch (e) {
          debugPrint('Error parsing cached message $key: $e');
        }
      }

      // Sort by timestamp descending (newest first)
      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      return messages;
    } catch (e) {
      debugPrint('Error getting cached messages: $e');
      return [];
    }
  }

  /// Delete a cached message
  Future<void> deleteMessage(String chatId, String messageId) async {
    try {
      final box = await _getMessageBox(chatId);
      if (box == null) return;

      await box.delete(messageId);
    } catch (e) {
      debugPrint('Error deleting cached message: $e');
    }
  }

  /// Update a cached message
  Future<void> updateMessage(String chatId, MessageModel message) async {
    await cacheMessage(chatId, message);
  }

  /// Clear all cached messages for a chat
  Future<void> clearChatCache(String chatId) async {
    try {
      final box = await _getMessageBox(chatId);
      if (box == null) return;

      await box.clear();
    } catch (e) {
      debugPrint('Error clearing chat cache: $e');
    }
  }

  /// Check if we have cached messages for a chat
  Future<bool> hasCachedMessages(String chatId) async {
    try {
      final box = await _getMessageBox(chatId);
      return box != null && box.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get the count of cached messages
  Future<int> getCachedMessageCount(String chatId) async {
    try {
      final box = await _getMessageBox(chatId);
      return box?.length ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Get last sync timestamp for a chat
  Future<DateTime?> getLastSyncTime(String chatId) async {
    try {
      final metaBox = Hive.box<Map>(_metadataBox);
      final data = metaBox.get('sync_$chatId');
      if (data != null && data['lastSync'] != null) {
        return DateTime.fromMillisecondsSinceEpoch(data['lastSync'] as int);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Update last sync time
  Future<void> _updateLastSync(String chatId) async {
    try {
      final metaBox = Hive.box<Map>(_metadataBox);
      await metaBox.put('sync_$chatId', {
        'lastSync': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('Error updating last sync: $e');
    }
  }

  /// Cleanup old messages to prevent storage bloat
  Future<void> _cleanupOldMessages(Box<Map> box) async {
    try {
      if (box.length <= _maxMessagesPerChat) return;

      // Get all messages with timestamps
      final messagesWithTime = <String, int>{};
      for (final key in box.keys) {
        final data = box.get(key);
        if (data != null && data['timestamp'] != null) {
          messagesWithTime[key.toString()] = data['timestamp'] as int;
        }
      }

      // Sort by timestamp and keep only recent ones
      final sortedKeys = messagesWithTime.keys.toList()
        ..sort((a, b) => messagesWithTime[b]!.compareTo(messagesWithTime[a]!));

      // Delete old messages
      final keysToDelete = sortedKeys.skip(_maxMessagesPerChat).toList();
      for (final key in keysToDelete) {
        await box.delete(key);
      }

      debugPrint('Cleaned up ${keysToDelete.length} old messages');
    } catch (e) {
      debugPrint('Error cleaning up old messages: $e');
    }
  }

  /// Close all open boxes (call on app dispose)
  Future<void> dispose() async {
    try {
      await Hive.close();
    } catch (e) {
      debugPrint('Error disposing MessageCacheService: $e');
    }
  }
}

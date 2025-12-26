import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage recently visited rooms history
class RoomVisitHistoryService {
  static const _key = 'room_visit_history_v1';
  static const _maxItems = 20;

  /// Get all visited rooms (most recent first)
  Future<List<Map<String, dynamic>>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_key) ?? <String>[];
    return jsonList
        .map((s) {
          try {
            return Map<String, dynamic>.from(json.decode(s) as Map);
          } catch (_) {
            return null;
          }
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Add a room to visit history
  Future<void> addRoom(Map<String, dynamic> room) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_key) ?? <String>[];
    
    // Get existing history
    final history = jsonList
        .map((s) {
          try {
            return Map<String, dynamic>.from(json.decode(s) as Map);
          } catch (_) {
            return null;
          }
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    // Create a minimal room object for storage (avoid storing too much data)
    final roomId = room['id']?.toString() ?? room['name']?.toString() ?? '';
    final roomData = {
      'id': roomId,
      'name': room['name'],
      'location': room['location'],
      'roomType': room['roomType'],
      'rentAmount': room['rentAmount'],
      'rentCurrency': room['rentCurrency'] ?? '₹',
      'visitedAt': DateTime.now().millisecondsSinceEpoch,
    };

    // Remove existing entry for same room (move to top)
    history.removeWhere((r) => r['id']?.toString() == roomId);
    
    // Insert at beginning
    history.insert(0, roomData);
    
    // Cap size
    if (history.length > _maxItems) {
      history.removeRange(_maxItems, history.length);
    }

    // Save back
    final newJsonList = history.map((r) => json.encode(r)).toList();
    await prefs.setStringList(_key, newJsonList);
  }

  /// Remove a specific room from history by index
  Future<void> removeAt(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_key) ?? <String>[];
    if (index < 0 || index >= jsonList.length) return;
    jsonList.removeAt(index);
    await prefs.setStringList(_key, jsonList);
  }

  /// Remove a specific room from history by ID
  Future<void> removeById(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_key) ?? <String>[];
    
    final history = jsonList
        .map((s) {
          try {
            return Map<String, dynamic>.from(json.decode(s) as Map);
          } catch (_) {
            return null;
          }
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    history.removeWhere((r) => r['id']?.toString() == roomId);
    
    final newJsonList = history.map((r) => json.encode(r)).toList();
    await prefs.setStringList(_key, newJsonList);
  }

  /// Clear all room visit history
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Check if history is empty
  Future<bool> isEmpty() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_key) ?? <String>[];
    return jsonList.isEmpty;
  }
}

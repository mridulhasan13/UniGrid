import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// NotifThreadStore
///
/// Persistent local storage manager for notification threads and message history.
/// Allows stacking multiple incoming messages per sender/conversation (WhatsApp style)
/// across both foreground and background app executions.
/// ─────────────────────────────────────────────────────────────────────────────
/// Result container for a notification thread containing the displayed lines (up to 8)
/// and the total accumulated notification count.
class NotifThreadResult {
  final List<String> lines;
  final int totalCount;

  const NotifThreadResult({
    required this.lines,
    required this.totalCount,
  });

  /// Formats the notification count badge.
  /// If totalCount is 10 or more, returns '10+ Notifications'.
  /// Otherwise returns e.g. '5 messages' or '4 updates'.
  String countLabel({String singular = 'message', String plural = 'messages'}) {
    if (totalCount >= 10) return '10+ Notifications';
    return '$totalCount ${totalCount == 1 ? singular : plural}';
  }
}

class NotifThreadStore {
  NotifThreadStore._();

  static const String _storageKey = 'unigrid_active_notif_threads_v1';
  static const int _maxLinesPerThread = 8; // Display up to 8 messages/announcements

  /// Loads all stored threads from persistent disk.
  static Future<Map<String, Map<String, dynamic>>> _loadRawThreads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString(_storageKey);
      if (rawJson == null || rawJson.isEmpty) return {};

      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      final result = <String, Map<String, dynamic>>{};
      decoded.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          result[key] = Map<String, dynamic>.from(value);
        }
      });
      return result;
    } catch (e) {
      debugPrint('[NotifThreadStore] Error loading threads: $e');
      return {};
    }
  }

  /// Saves the thread map back to persistent disk.
  static Future<void> _saveRawThreads(
      Map<String, Map<String, dynamic>> threads) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(threads));
    } catch (e) {
      debugPrint('[NotifThreadStore] Error saving threads: $e');
    }
  }

  /// Appends a new message line to the given [threadKey] (e.g. senderUserId or 'group_chat').
  /// Keeps the latest 8 messages on display while tracking the exact total notification count.
  /// Returns a [NotifThreadResult] with lines and count.
  static Future<NotifThreadResult> addMessage({
    required String threadKey,
    required String senderName,
    required String messageText,
  }) async {
    if (threadKey.isEmpty || messageText.isEmpty) {
      return const NotifThreadResult(lines: [], totalCount: 0);
    }

    final threads = await _loadRawThreads();
    final threadData = threads[threadKey] ??
        {
          'senderName': senderName,
          'lines': <String>[],
          'count': 0,
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        };

    final rawLines = (threadData['lines'] as List<dynamic>?) ?? [];
    final List<String> lines = rawLines.map((e) => e.toString()).toList();
    int count = (threadData['count'] as num?)?.toInt() ?? lines.length;
    count += 1;

    // Append new message line
    lines.add(messageText.trim());

    // Keep only the most recent 8 lines on display
    while (lines.length > _maxLinesPerThread) {
      lines.removeAt(0);
    }

    threadData['senderName'] = senderName.isNotEmpty
        ? senderName
        : (threadData['senderName'] ?? 'UniGrid');
    threadData['lines'] = lines;
    threadData['count'] = count;
    threadData['lastUpdated'] = DateTime.now().millisecondsSinceEpoch;

    threads[threadKey] = threadData;
    await _saveRawThreads(threads);

    return NotifThreadResult(lines: lines, totalCount: count);
  }

  /// Retrieves the current stacked lines for a thread.
  static Future<List<String>> getLines(String threadKey) async {
    final threads = await _loadRawThreads();
    final threadData = threads[threadKey];
    if (threadData == null) return [];
    final rawLines = (threadData['lines'] as List<dynamic>?) ?? [];
    return rawLines.map((e) => e.toString()).toList();
  }

  /// Retrieves all active threads: Map of threadKey -> { 'senderName': String, 'lines': List<String> }
  static Future<Map<String, Map<String, dynamic>>> getAllThreads() async {
    return await _loadRawThreads();
  }

  /// Returns total count of unread messages across all active sender threads.
  static Future<int> getTotalUnreadCount() async {
    final threads = await _loadRawThreads();
    int total = 0;
    threads.forEach((_, data) {
      final count = (data['count'] as num?)?.toInt();
      if (count != null && count > 0) {
        total += count;
      } else {
        final lines = (data['lines'] as List<dynamic>?) ?? [];
        total += lines.length;
      }
    });
    return total;
  }

  /// Validates if an existing notification for [notifId] (and optional [tag]) is currently
  /// active in the system tray. If it was dismissed/swiped by the user, clears the stored thread first.
  static Future<void> syncWithActiveNotifications({
    required dynamic localNotif,
    required String threadKey,
    required int notifId,
    String? tag,
  }) async {
    if (threadKey.isEmpty) return;
    try {
      final dynamic activeList = await localNotif.getActiveNotifications();
      if (activeList is List) {
        final isActive = activeList.any((n) {
          try {
            if (n.id != notifId) return false;
            if (tag != null && tag.isNotEmpty && n.tag != null && n.tag != tag) {
              return false;
            }
            return true;
          } catch (_) {
            return false;
          }
        });
        if (!isActive) {
          // The user swiped away or dismissed the previous notification from the status bar
          await clearThread(threadKey);
        }
      }
    } catch (e) {
      debugPrint('[NotifThreadStore] syncWithActiveNotifications error: $e');
    }
  }

  /// Clears lines for a specific thread (e.g. when user opens a private chat with that sender).
  static Future<void> clearThread(String threadKey) async {
    if (threadKey.isEmpty) return;
    final threads = await _loadRawThreads();
    if (threads.containsKey(threadKey)) {
      threads.remove(threadKey);
      await _saveRawThreads(threads);
      debugPrint('[NotifThreadStore] Cleared thread for "$threadKey"');
    }
  }

  /// Wipes all cached notification threads (e.g. when user taps 'Clear All' or clears notifications).
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      debugPrint('[NotifThreadStore] Cleared all stored threads');
    } catch (e) {
      debugPrint('[NotifThreadStore] Error clearing all threads: $e');
    }
  }
}

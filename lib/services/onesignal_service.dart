import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart';

class OneSignalService {
  static const String _appId = '6b15bde4-2a01-41cd-8f09-041176ed175c';
  static const String _restApiKey =
      'os_v2_app_nmk33zbkafa43dyjaqixn3ixlsudwaqx43teoa5cjvyjaio5o3lm2vln4fbbyhnoi4l5wox6j3ajmodi6euu4pktlur6nlifzjwe3aq';

  // OneSignal v2 REST API endpoint
  static const String _apiUrl = 'https://api.onesignal.com/notifications';

  static Future<void> initialize() async {
    if (kIsWeb) return;
    OneSignal.initialize(_appId);
    await OneSignal.Notifications.requestPermission(true);
  }

  static void setExternalUserId(String userId) {
    if (kIsWeb) return;
    OneSignal.login(userId);
  }

  static void setTags(String department, String batch) {
    if (kIsWeb) return;
    if (department.isEmpty || batch.isEmpty) return;
    OneSignal.User.addTags({
      'department': department,
      'batch': batch,
    });
  }

  static void removeExternalUserId() {
    if (kIsWeb) return;
    OneSignal.logout();
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Key $_restApiKey',
        'accept': 'application/json',
      };

  /// Sends a push notification to ALL subscribed users
  static Future<void> sendNotificationToAll({
    required String title,
    required String body,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: _headers,
        body: jsonEncode({
          'app_id': _appId,
          'included_segments': ['All'],
          'headings': {'en': title},
          'contents': {'en': body},
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Broadcast notification sent!');
      } else {
        debugPrint(
            '❌ Broadcast failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');
    }
  }

  /// Sends a push notification to users in a SPECIFIC department and batch
  static Future<void> sendNotificationToDeptAndBatch({
    required String department,
    required String batch,
    required String title,
    required String body,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: _headers,
        body: jsonEncode({
          'app_id': _appId,
          'filters': [
            {'field': 'tag', 'key': 'department', 'relation': '=', 'value': department},
            {'operator': 'AND'},
            {'field': 'tag', 'key': 'batch', 'relation': '=', 'value': batch}
          ],
          'headings': {'en': title},
          'contents': {'en': body},
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Department/Batch-scoped notification sent!');
      } else {
        debugPrint(
            '❌ Scoped notification failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error sending scoped notification: $e');
    }
  }

  /// Sends a push notification to a SPECIFIC user by their Firebase UID
  static Future<void> sendPrivateNotification({
    required String recipientId,
    required String title,
    required String body,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: _headers,
        body: jsonEncode({
          'app_id': _appId,
          'target_channel': 'push',
          'include_aliases': {
            'external_id': [recipientId],
          },
          'headings': {'en': title},
          'contents': {'en': body},
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Private notification sent to $recipientId!');
      } else {
        debugPrint('❌ Private failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error sending private notification: $e');
    }
  }

  // ── Shortcut helpers ──────────────────────────────────────────────────────

  static Future<void> notifyNewAnnouncement({
    required String title,
    required String type,
    required String department,
    required String batch,
  }) async {
    await sendNotificationToDeptAndBatch(
      department: department,
      batch: batch,
      title: '📢 New ${type.isNotEmpty ? type : "Announcement"}',
      body: title,
    );
  }

  static Future<void> notifyNewMaterial({
    required String title,
    required String subject,
    required String department,
    required String batch,
  }) async {
    await sendNotificationToDeptAndBatch(
      department: department,
      batch: batch,
      title: '📚 New Material Uploaded',
      body: '$title${subject.isNotEmpty ? ' · $subject' : ''}',
    );
  }

  static Future<void> notifyNewMessage({
    required String senderName,
    required String text,
    required String department,
    required String batch,
  }) async {
    final preview = text.length > 80 ? '${text.substring(0, 80)}...' : text;
    await sendNotificationToDeptAndBatch(
      department: department,
      batch: batch,
      title: '💬 $senderName',
      body: preview,
    );
  }
}

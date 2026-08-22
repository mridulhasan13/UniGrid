import 'package:flutter/foundation.dart' show debugPrint;
import '../shared/token_resolver.dart';
import '../shared/fcm_dispatcher.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// WWSender  —  Web → Web
///
/// Sends push notifications exclusively to browser (web) FCM tokens.
/// ─────────────────────────────────────────────────────────────────────────────
class WWSender {
  WWSender._();

  // ─── Private (Direct Message) ────────────────────────────────────────────

  static Future<void> sendPrivate({
    required String title,
    required String body,
    required String senderUserId,
    required String recipientId,
    required String messageId,
    Map<String, String>? extraData,
  }) async {
    final prefField = extraData?['preferenceField'] ?? 'notifChat';
    final tokens = await TokenResolver.getWebTokensForUser(
      recipientId,
      requiredPreferenceField: prefField,
    );
    if (tokens.isEmpty) {
      debugPrint('[WWSender] No web tokens for recipient $recipientId (or notifications disabled)');
      return;
    }
    await FcmDispatcher.dispatch(
      tokens: tokens,
      title: title,
      body: body,
      senderUserId: senderUserId,
      messageId: messageId,
      targetPlatform: 'web',
      extraData: extraData,
    );
    debugPrint('[WWSender] Private → ${tokens.length} web token(s)');
  }

  // ─── Broadcast (Dept + Batch) ────────────────────────────────────────────

  static Future<void> sendBroadcast({
    required String title,
    required String body,
    required String senderUserId,
    required String department,
    required String batch,
    bool adminsOnly = false,
    required String messageId,
    Map<String, String>? extraData,
  }) async {
    final prefField = extraData?['preferenceField'] ??
        (extraData?['target'] == 'group_chat' ? 'notifChat' : 'notifAlerts');
    final tokens = await TokenResolver.getWebTokensForGroup(
      department: department,
      batch: batch,
      adminsOnly: adminsOnly,
      excludeUserId: senderUserId,
      requiredPreferenceField: prefField,
    );
    if (tokens.isEmpty) {
      debugPrint('[WWSender] No web tokens in $department-$batch for $prefField');
      return;
    }
    await FcmDispatcher.dispatch(
      tokens: tokens,
      title: title,
      body: body,
      senderUserId: senderUserId,
      messageId: messageId,
      targetPlatform: 'web',
      extraData: extraData,
    );
    debugPrint('[WWSender] Broadcast → ${tokens.length} web token(s)');
  }
}

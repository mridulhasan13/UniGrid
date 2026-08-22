import 'package:flutter/foundation.dart' show debugPrint;
import '../shared/token_resolver.dart';
import '../shared/fcm_dispatcher.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// AASender  —  App → App
///
/// Sends push notifications exclusively to native (Android / iOS) FCM tokens.
/// ─────────────────────────────────────────────────────────────────────────────
class AASender {
  AASender._();

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
    final tokens = await TokenResolver.getNativeTokensForUser(
      recipientId,
      requiredPreferenceField: prefField,
    );
    if (tokens.isEmpty) {
      debugPrint('[AASender] No native tokens for recipient $recipientId (or notifications disabled)');
      return;
    }
    await FcmDispatcher.dispatch(
      tokens: tokens,
      title: title,
      body: body,
      senderUserId: senderUserId,
      messageId: messageId,
      targetPlatform: 'native',
      extraData: extraData,
    );
    debugPrint('[AASender] Private → ${tokens.length} native token(s)');
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
    final tokens = await TokenResolver.getNativeTokensForGroup(
      department: department,
      batch: batch,
      adminsOnly: adminsOnly,
      excludeUserId: senderUserId,
      requiredPreferenceField: prefField,
    );
    if (tokens.isEmpty) {
      debugPrint('[AASender] No native tokens in $department-$batch for $prefField');
      return;
    }
    await FcmDispatcher.dispatch(
      tokens: tokens,
      title: title,
      body: body,
      senderUserId: senderUserId,
      messageId: messageId,
      targetPlatform: 'native',
      extraData: extraData,
    );
    debugPrint('[AASender] Broadcast → ${tokens.length} native token(s)');
  }
}

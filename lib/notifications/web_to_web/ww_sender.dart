import 'package:flutter/foundation.dart' show debugPrint;
import '../shared/token_resolver.dart';
import '../shared/fcm_dispatcher.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// WWSender  —  Web → Web
///
/// Sends push notifications exclusively to browser (web) FCM tokens.
/// Called when the sender is running in a web browser and the intended
/// recipients are also web browser sessions.
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
  }) async {
    final tokens = await TokenResolver.getWebTokensForUser(recipientId);
    if (tokens.isEmpty) {
      debugPrint('[WWSender] No web tokens for recipient $recipientId');
      return;
    }
    await FcmDispatcher.dispatch(
      tokens: tokens,
      title: title,
      body: body,
      senderUserId: senderUserId,
      messageId: messageId,
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
  }) async {
    final tokens = await TokenResolver.getWebTokensForGroup(
      department: department,
      batch: batch,
      adminsOnly: adminsOnly,
      excludeUserId: senderUserId,
    );
    if (tokens.isEmpty) {
      debugPrint('[WWSender] No web tokens in $department-$batch');
      return;
    }
    await FcmDispatcher.dispatch(
      tokens: tokens,
      title: title,
      body: body,
      senderUserId: senderUserId,
      messageId: messageId,
    );
    debugPrint('[WWSender] Broadcast → ${tokens.length} web token(s)');
  }
}

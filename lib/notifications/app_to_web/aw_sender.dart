import 'package:flutter/foundation.dart' show debugPrint;
import '../shared/token_resolver.dart';
import '../shared/fcm_dispatcher.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// AWSender  —  App → Web
///
/// Sends push notifications exclusively to browser (web) FCM tokens.
/// Called when the sender is running on a native device (Android / iOS)
/// and the intended recipients are web browser sessions.
/// ─────────────────────────────────────────────────────────────────────────────
class AWSender {
  AWSender._();

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
      debugPrint('[AWSender] No web tokens for recipient $recipientId');
      return;
    }
    await FcmDispatcher.dispatch(
      tokens: tokens,
      title: title,
      body: body,
      senderUserId: senderUserId,
      messageId: messageId,
    );
    debugPrint('[AWSender] Private → ${tokens.length} web token(s)');
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
      debugPrint('[AWSender] No web tokens in $department-$batch');
      return;
    }
    await FcmDispatcher.dispatch(
      tokens: tokens,
      title: title,
      body: body,
      senderUserId: senderUserId,
      messageId: messageId,
    );
    debugPrint('[AWSender] Broadcast → ${tokens.length} web token(s)');
  }
}

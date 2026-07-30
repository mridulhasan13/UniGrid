import 'package:flutter/foundation.dart' show debugPrint;
import '../shared/token_resolver.dart';
import '../shared/fcm_dispatcher.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// WASender  —  Web → App
///
/// Sends push notifications exclusively to native (Android / iOS) FCM tokens.
/// ─────────────────────────────────────────────────────────────────────────────
class WASender {
  WASender._();

  // ─── Private (Direct Message) ────────────────────────────────────────────

  static Future<void> sendPrivate({
    required String title,
    required String body,
    required String senderUserId,
    required String recipientId,
    required String messageId,
  }) async {
    final tokens = await TokenResolver.getNativeTokensForUser(recipientId);
    if (tokens.isEmpty) {
      debugPrint('[WASender] No native tokens for recipient $recipientId');
      return;
    }
    await FcmDispatcher.dispatch(
      tokens: tokens,
      title: title,
      body: body,
      senderUserId: senderUserId,
      messageId: messageId,
      targetPlatform: 'native',
    );
    debugPrint('[WASender] Private → ${tokens.length} native token(s)');
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
    final tokens = await TokenResolver.getNativeTokensForGroup(
      department: department,
      batch: batch,
      adminsOnly: adminsOnly,
      excludeUserId: senderUserId,
    );
    if (tokens.isEmpty) {
      debugPrint('[WASender] No native tokens in $department-$batch');
      return;
    }
    await FcmDispatcher.dispatch(
      tokens: tokens,
      title: title,
      body: body,
      senderUserId: senderUserId,
      messageId: messageId,
      targetPlatform: 'native',
    );
    debugPrint('[WASender] Broadcast → ${tokens.length} native token(s)');
  }
}

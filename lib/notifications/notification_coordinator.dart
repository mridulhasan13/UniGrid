import 'package:flutter/foundation.dart';

import 'web_to_web/ww_sender.dart';
import 'web_to_web/ww_receiver.dart';
import 'web_to_app/wa_sender.dart';
import 'web_to_app/wa_receiver.dart';
import 'app_to_web/aw_sender.dart';
import 'app_to_web/aw_receiver.dart';
import 'app_to_app/aa_sender.dart';
import 'app_to_app/aa_receiver.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// NotificationCoordinator
///
/// Single entry point for the 4-path notification system.
///
/// ARCHITECTURE OVERVIEW
/// ─────────────────────
///
///   Sender platform \  Recipient type │  Sender used   │  Receiver used
///   ────────────────┼─────────────────┼────────────────┼────────────────
///   Web             │  Web tokens     │  WWSender      │  WWReceiver
///   Web             │  Native tokens  │  WASender      │  WAReceiver
///   App (Native)    │  Web tokens     │  AWSender      │  AWReceiver*
///   App (Native)    │  Native tokens  │  AASender      │  AAReceiver*
///
///   * AWReceiver delegates to WWReceiver (same web handler)
///   * AAReceiver delegates to WAReceiver (same native handler)
///
/// DUPLICATE PREVENTION
/// ─────────────────────
///   • Web receivers share one onMessage listener (initialized once via WWReceiver)
///   • Native receivers share one onMessage listener (initialized once via WAReceiver)
///   • DuplicateGuard blocks the same messageId from displaying twice
///   • Android OS deduplicates via notification `tag` (same messageId = same tag)
///   • Sender's own device token is always excluded before dispatch
///
/// SOUND
/// ─────
///   • Web foreground : Web Audio API ding-dong (sound_helper_web.dart)
///   • Web background : OS system sound via Service Worker showNotification
///   • Native foreground : flutter_local_notifications with playSound: true
///   • Native background : FCM payload android.notification.sound = "default"
///
/// USAGE
/// ─────
///   // In main.dart (after Firebase.initializeApp):
///   await NotificationCoordinator.init();
///
///   // From any screen:
///   await NotificationCoordinator.sendPrivate(
///     title: 'John', body: 'Hey!',
///     senderUserId: me.id, recipientId: them.id, messageId: 'pm_xxx',
///   );
///
///   await NotificationCoordinator.sendBroadcast(
///     title: 'Notice', body: 'Class cancelled',
///     senderUserId: me.id, department: 'IPE', batch: '51',
///     messageId: 'bc_yyy',
///   );
/// ─────────────────────────────────────────────────────────────────────────────
class NotificationCoordinator {
  NotificationCoordinator._();

  static bool _initialized = false;

  // ─── Init ─────────────────────────────────────────────────────────────────

  /// Call once in [main()] after [Firebase.initializeApp()].
  /// Sets up all receivers for the current platform.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) {
      // Web platform: one shared onMessage listener (handles WW + AW paths)
      WWReceiver.init();
      AWReceiver.init(); // delegates to WWReceiver — safe to call, no-op if already done
      debugPrint('[NotificationCoordinator] ✓ Web receivers ready');
    } else {
      // Native platform: one shared onMessage listener (handles WA + AA paths)
      await WAReceiver.init();
      await AAReceiver.init(); // delegates to WAReceiver — safe to call
      debugPrint('[NotificationCoordinator] ✓ Native receivers ready');
    }

    debugPrint('[NotificationCoordinator] ✓ 4-path notification system initialized');
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Send a private (direct) notification to [recipientId].
  ///
  /// Automatically routes through:
  ///   • [WWSender] → recipient's web tokens
  ///   • [WASender] → recipient's native tokens   (if sender is web)
  ///   • [AWSender] → recipient's web tokens
  ///   • [AASender] → recipient's native tokens   (if sender is native)
  ///
  /// Both web and native tokens are targeted so the recipient gets the
  /// notification on ALL their active devices simultaneously.
  static Future<void> sendPrivate({
    required String title,
    required String body,
    required String senderUserId,
    required String recipientId,
    String? messageId,
    Map<String, String>? extraData,
  }) async {
    final msgId = messageId ??
        'pm_${senderUserId.substring(0, 6)}_${DateTime.now().millisecondsSinceEpoch}';

    final payloadData = {
      'target': 'private_chat',
      'type': 'private_chat',
      'route': '/private_chat',
      'senderUserId': senderUserId,
      'recipientId': recipientId,
      'preferenceField': 'notifChat',
      ...?extraData,
    };

    if (kIsWeb) {
      // ── Web sender ──────────────────────────────────────────────────────
      await Future.wait([
        WWSender.sendPrivate(
          title: title, body: body,
          senderUserId: senderUserId, recipientId: recipientId,
          messageId: msgId,
          extraData: payloadData,
        ),
        WASender.sendPrivate(
          title: title, body: body,
          senderUserId: senderUserId, recipientId: recipientId,
          messageId: msgId,
          extraData: payloadData,
        ),
      ]);
    } else {
      // ── Native sender ───────────────────────────────────────────────────
      await Future.wait([
        AWSender.sendPrivate(
          title: title, body: body,
          senderUserId: senderUserId, recipientId: recipientId,
          messageId: msgId,
          extraData: payloadData,
        ),
        AASender.sendPrivate(
          title: title, body: body,
          senderUserId: senderUserId, recipientId: recipientId,
          messageId: msgId,
          extraData: payloadData,
        ),
      ]);
    }
  }

  /// Send a broadcast notification to all members of [department]+[batch].
  ///
  /// Pass [adminsOnly: true] to restrict to CRs and admins.
  static Future<void> sendBroadcast({
    required String title,
    required String body,
    required String senderUserId,
    required String department,
    required String batch,
    bool adminsOnly = false,
    String? messageId,
    Map<String, String>? extraData,
  }) async {
    final msgId = messageId ??
        'bc_${department}_${batch}_${DateTime.now().millisecondsSinceEpoch}';

    if (kIsWeb) {
      // ── Web sender ──────────────────────────────────────────────────────
      await Future.wait([
        WWSender.sendBroadcast(
          title: title, body: body,
          senderUserId: senderUserId, department: department, batch: batch,
          adminsOnly: adminsOnly, messageId: msgId,
          extraData: extraData,
        ),
        WASender.sendBroadcast(
          title: title, body: body,
          senderUserId: senderUserId, department: department, batch: batch,
          adminsOnly: adminsOnly, messageId: msgId,
          extraData: extraData,
        ),
      ]);
    } else {
      // ── Native sender ───────────────────────────────────────────────────
      await Future.wait([
        AWSender.sendBroadcast(
          title: title, body: body,
          senderUserId: senderUserId, department: department, batch: batch,
          adminsOnly: adminsOnly, messageId: msgId,
          extraData: extraData,
        ),
        AASender.sendBroadcast(
          title: title, body: body,
          senderUserId: senderUserId, department: department, batch: batch,
          adminsOnly: adminsOnly, messageId: msgId,
          extraData: extraData,
        ),
      ]);
    }
  }
}

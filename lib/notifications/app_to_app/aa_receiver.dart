import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import '../web_to_app/wa_receiver.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// AAReceiver  —  App → App  (receiver side, runs on Android / iOS)
///
/// The receiver side of App→App is functionally identical to Web→App receiving:
/// both paths deliver a native FCM push to an Android/iOS device, displayed as
/// a system-tray notification (with sound) + in-app banner when in foreground.
///
/// This class delegates entirely to [WAReceiver] — there is only one native
/// foreground listener needed regardless of where the sender is running.
/// ─────────────────────────────────────────────────────────────────────────────
class AAReceiver {
  AAReceiver._();

  static Future<void> init() async {
    if (kIsWeb) return;
    await WAReceiver.init(); // single shared native listener handles both WA and AA
    debugPrint('[AAReceiver] ✓ Delegated to WAReceiver (shared native listener)');
  }
}

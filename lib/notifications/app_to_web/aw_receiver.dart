import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import '../web_to_web/ww_receiver.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// AWReceiver  —  App → Web  (receiver side, runs in the browser)
///
/// The receiver side of App→Web is functionally identical to Web→Web receiving:
/// both paths deliver a web push to a browser session, which is then displayed
/// with sound + in-app banner.
///
/// This class delegates entirely to [WWReceiver] — there is only one web
/// foreground listener needed regardless of where the sender is running.
/// ─────────────────────────────────────────────────────────────────────────────
class AWReceiver {
  AWReceiver._();

  static void init() {
    if (!kIsWeb) return;
    WWReceiver.init(); // single shared web listener handles both WW and AW
    debugPrint('[AWReceiver] ✓ Delegated to WWReceiver (shared web listener)');
  }
}

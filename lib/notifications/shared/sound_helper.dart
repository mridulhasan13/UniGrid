// Conditional export — picks the right implementation at compile time:
//   • Web    → sound_helper_web.dart  (Web Audio API ding-dong)
//   • Native → sound_helper_stub.dart (no-op; sound comes from FCM payload)
export 'sound_helper_stub.dart'
    if (dart.library.js) 'sound_helper_web.dart';

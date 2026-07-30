// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;

/// Web implementation — synthesises a short notification "ding" using the
/// Web Audio API (no audio file needed, works offline, no autoplay block).
///
/// Browsers allow AudioContext creation in user-gesture callbacks.
/// Since onMessage fires after a server push (not a click), we wrap in try/catch
/// in case the browser blocks it; graceful degradation to silent in-app banner.
void playNotificationSound() {
  try {
    js.context.callMethod('eval', [r'''
      (function() {
        try {
          var AudioCtx = window.AudioContext || window.webkitAudioContext;
          if (!AudioCtx) return;
          var ctx = new AudioCtx();

          // First tone: 880 Hz (A5)
          var osc1 = ctx.createOscillator();
          var gain1 = ctx.createGain();
          osc1.connect(gain1); gain1.connect(ctx.destination);
          osc1.type = 'sine';
          osc1.frequency.setValueAtTime(880, ctx.currentTime);
          gain1.gain.setValueAtTime(0.35, ctx.currentTime);
          gain1.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.25);
          osc1.start(ctx.currentTime);
          osc1.stop(ctx.currentTime + 0.25);

          // Second tone: 1100 Hz — played slightly after for a "ding-dong" feel
          var osc2 = ctx.createOscillator();
          var gain2 = ctx.createGain();
          osc2.connect(gain2); gain2.connect(ctx.destination);
          osc2.type = 'sine';
          osc2.frequency.setValueAtTime(1100, ctx.currentTime + 0.15);
          gain2.gain.setValueAtTime(0.25, ctx.currentTime + 0.15);
          gain2.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.55);
          osc2.start(ctx.currentTime + 0.15);
          osc2.stop(ctx.currentTime + 0.55);
        } catch(e) {
          // Silently ignore — in-app banner still shows without sound
        }
      })();
    ''']);
  } catch (_) {
    // dart:js interop unavailable — ignore
  }
}

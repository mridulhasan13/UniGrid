// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

void notifyAppLoaded() {
  try {
    html.window.dispatchEvent(html.CustomEvent('flutter-first-frame'));
  } catch (_) {}
  try {
    js.context.callMethod('_onAppLoaded');
  } catch (_) {}
}


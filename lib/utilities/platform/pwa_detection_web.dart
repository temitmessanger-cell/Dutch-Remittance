// Real web implementation — only compiled when targeting Flutter web.
// Uses dart:html which is only available in a browser context.

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// True when the app is running as an installed PWA (standalone mode).
/// This covers:
///   • Android: installed via Chrome "Add to Home Screen"
///   • iOS:     added to home screen from Safari
///   • Desktop: installed via Chromium-based browsers
bool get isPwaMode {
  // display-mode: standalone = installed PWA on Android/Desktop
  final standaloneQuery = html.window.matchMedia('(display-mode: standalone)');
  if (standaloneQuery.matches) return true;

  // navigator.standalone = installed PWA on iOS Safari
  final jsStandalone = (html.window.navigator as dynamic).standalone;
  if (jsStandalone == true) return true;

  // Android TWA (Trusted Web Activity) opens with this referrer
  final referrer = html.document.referrer;
  if (referrer.startsWith('android-app://')) return true;

  return false;
}

/// True when the app is running in a regular browser tab (NOT installed).
bool get isBrowserMode => !isPwaMode;

/// Listen to messages forwarded from the service worker via
/// the `dr_sw_message` custom event (dispatched by index.html).
void registerSwMessageListener(void Function(Map<String, dynamic>) onMessage) {
  html.window.addEventListener('dr_sw_message', (event) {
    if (event is html.CustomEvent) {
      final detail = event.detail;
      if (detail is Map) {
        onMessage(Map<String, dynamic>.from(detail));
      }
    }
  });
}

/// Returns the last service-worker install message, allowing Flutter to catch
/// up when the worker finished before the app listener was attached.
Map<String, dynamic>? getLastSwMessage() {
  final value = (html.window as dynamic).__DR_SW_LAST_MSG__;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

bool get canInstallPwa => (html.window as dynamic).dutchRemitCanInstall == true;

void triggerInstallPrompt() {
  try {
    (html.window as dynamic).dutchRemitTriggerInstall();
  } catch (_) {}
}

void reloadPage() {
  html.window.location.reload();
}

/// Clear any saved URL so the browser doesn't try to restore
/// a deep link that would bypass the login screen.
void removeSavedUrl() {
  try {
    html.window.history.replaceState(null, '', '/');
  } catch (_) {}
}

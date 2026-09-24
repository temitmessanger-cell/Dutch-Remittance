// Stub implementation — used on iOS, Android and desktop.
// The real implementation lives in pwa_detection_web.dart.

bool get isPwaMode => false;

Map<String, dynamic>? getLastSwMessage() => null;
bool get canInstallPwa => false;
void triggerInstallPrompt() {}
void reloadPage() {}
bool get isBrowserMode => false;

void registerSwMessageListener(void Function(Map<String, dynamic>) onMessage) {}
void removeSavedUrl() {}

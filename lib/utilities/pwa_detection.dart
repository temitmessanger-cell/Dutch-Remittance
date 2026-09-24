/// Platform-aware PWA detection.
///
/// On web builds this delegates to [pwa_detection_web.dart] via dart:html.
/// On all other platforms (iOS, Android, desktop) the stub returns safe
/// defaults (isPwaMode = false).
///
/// Usage:
/// ```dart
/// import 'package:dutch_remit/utilities/pwa_detection.dart';
///
/// if (isPwaMode) { ... }
/// ```
library pwa_detection;

export 'platform/pwa_detection_stub.dart'
    if (dart.library.html) 'platform/pwa_detection_web.dart';

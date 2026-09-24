import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dutch_remit/utilities/pwa_detection.dart';

/// Bridges service-worker install-progress messages to Flutter.
///
/// The service worker (sw.js) sends postMessage events which index.html
/// forwards as `dr_sw_message` CustomEvents on window. This class
/// converts those events into a Dart stream consumed by [OfflineSetupScreen].
///
/// On non-web platforms it emits a single INSTALL_COMPLETE immediately
/// so the setup screen finishes instantly (no SW on native).
class OfflineSetupBridge {
  OfflineSetupBridge._();
  static final OfflineSetupBridge instance = OfflineSetupBridge._();

  final StreamController<SwMessage> _controller =
      StreamController<SwMessage>.broadcast();

  Stream<SwMessage> get messages => _controller.stream;

  bool _listening = false;

  void startListening() {
    if (_listening) return;
    _listening = true;

    if (!kIsWeb) {
      // Native — no service worker, emit complete immediately
      Future.microtask(() => _controller.add(
          const SwMessage(type: SwMessageType.complete, cached: 0, total: 0)));
      return;
    }

    // Web — register the JS event listener via pwa_detection.dart
    registerSwMessageListener(_onRawMessage);

    // Replay the last message if the service worker finished before Flutter
    // attached its listener.
    final last = getLastSwMessage();
    if (last != null) _onRawMessage(last);
  }

  void _onRawMessage(Map<String, dynamic> msg) {
    final type   = msg['type']?.toString() ?? '';
    final cached = (msg['cached'] as num?)?.toInt() ?? 0;
    final total  = (msg['total']  as num?)?.toInt() ?? 0;
    final error  = msg['error']?.toString();

    SwMessageType kind;
    switch (type) {
      case 'INSTALL_PROGRESS': kind = SwMessageType.progress; break;
      case 'INSTALL_COMPLETE': kind = SwMessageType.complete; break;
      case 'INSTALL_ERROR':    kind = SwMessageType.error;    break;
      default: return;
    }

    _controller.add(SwMessage(type: kind, cached: cached, total: total, error: error));
  }

  void dispose() {
    _controller.close();
  }
}

enum SwMessageType { progress, complete, error }

class SwMessage {
  final SwMessageType type;
  final int           cached;
  final int           total;
  final String?       error;

  const SwMessage({
    required this.type,
    required this.cached,
    required this.total,
    this.error,
  });

  double get ratio => total > 0 ? (cached / total).clamp(0.0, 1.0) : 0.0;
}

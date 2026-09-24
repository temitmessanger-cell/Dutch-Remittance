import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Singleton that monitors network connectivity and exposes a stream
/// consumed by [OfflineActionGuard] and any screen that needs to react
/// to connectivity changes (e.g. deposit screen pausing mid-download).
///
/// Usage:
/// ```dart
/// // One-time check
/// if (!ConnectivityService.instance.isOnline) { ... }
///
/// // React to changes
/// ConnectivityService.instance.stream.listen((isOnline) { ... });
/// ```
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  late final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  bool _isOnline = true;
  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;

  Stream<bool> get stream => _controller.stream;

  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Call once in [main()] before [runApp()].
  Future<void> initialize() async {
    // Get initial state
    final results = await _connectivity.checkConnectivity();
    _isOnline = _resultsToOnline(results);

    // Subscribe to changes
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final nowOnline = _resultsToOnline(results);
      if (nowOnline != _isOnline) {
        _isOnline = nowOnline;
        _controller.add(_isOnline);
        debugPrint('[Connectivity] ${_isOnline ? "Online" : "Offline"}');
      }
    });
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }

  bool _resultsToOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi   ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn   ||
        r == ConnectivityResult.other);
  }

  /// Returns a future that resolves when connectivity is restored.
  Future<void> waitForOnline() {
    if (_isOnline) return Future.value();
    final completer = Completer<void>();
    late StreamSubscription<bool> sub;
    sub = stream.listen((isOnline) {
      if (isOnline) {
        sub.cancel();
        completer.complete();
      }
    });
    return completer.future;
  }
}

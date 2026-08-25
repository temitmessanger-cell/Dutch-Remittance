import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Tracks whether the guided product tour has been shown before, so it
/// only auto-plays once per device — but can always be replayed manually
/// (e.g. from Settings) for demos.
class ProductTourStorage {
  static const String boxName = 'dutch_remit_product_tour';
  static const String _dataKey = 'hasSeenTour';

  /// A lightweight signal Settings (or anywhere else) can flip to ask the
  /// tab shell to replay the tour, without needing a direct reference to
  /// its State — avoids threading a callback through every screen in
  /// between just for this one occasional action.
  static final ValueNotifier<int> replayRequested = ValueNotifier<int>(0);

  static void requestReplay() {
    replayRequested.value++;
  }

  Future<Box> get _box async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return Hive.openBox(boxName);
  }

  Future<bool> get hasSeenTour async {
    try {
      final box = await _box;
      return box.get(_dataKey, defaultValue: false) as bool;
    } catch (e) {
      return false;
    }
  }

  Future<void> markTourSeen() async {
    try {
      final box = await _box;
      await box.put(_dataKey, true);
    } catch (e) {
      // non-critical — worst case the tour replays once more than intended
    }
  }

  Future<void> resetTourSeen() async {
    try {
      final box = await _box;
      await box.put(_dataKey, false);
    } catch (e) {}
  }
}

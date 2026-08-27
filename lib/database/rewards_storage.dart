import 'package:hive/hive.dart';

/// Tracks whether the Tasks & Rewards explainer popup has been shown
/// before, so it only appears once per device on first entry to the
/// hub — mirrors the same open-or-create Hive box pattern used by
/// ProductTourStorage.
class RewardsStorage {
  static const String boxName = 'dutch_remit_rewards';
  static const String _explainerSeenKey = 'hasSeenRewardsExplainer';

  Future<Box> get _box async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return Hive.openBox(boxName);
  }

  Future<bool> get hasSeenExplainer async {
    try {
      final box = await _box;
      return box.get(_explainerSeenKey, defaultValue: false) as bool;
    } catch (e) {
      return false;
    }
  }

  Future<void> markExplainerSeen() async {
    try {
      final box = await _box;
      await box.put(_explainerSeenKey, true);
    } catch (e) {
      // non-critical — worst case the explainer shows once more than intended
    }
  }
}

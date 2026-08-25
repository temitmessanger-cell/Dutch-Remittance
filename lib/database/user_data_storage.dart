import 'package:hive/hive.dart';

/// Persists the logged-in user's profile data.
///
/// Backed by Hive — works on mobile, desktop, and web. The previous
/// dart:io File implementation had no web support, so this data never
/// actually persisted in a browser. Public API is unchanged.
class UserDataStorage {
  static const String boxName = 'dutch_remit_user_data';
  static const String _dataKey = 'user';

  Future<Box> get _box async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return Hive.openBox(boxName);
  }

  /// Recursively converts Hive's loosely-typed maps/lists into the
  /// strictly-typed Map<String, dynamic> / List<dynamic> shape the rest
  /// of the app expects (the same shape jsonDecode used to produce).
  dynamic _normalize(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _normalize(v)));
    } else if (value is List) {
      return value.map(_normalize).toList();
    }
    return value;
  }

  Future<Map<String, dynamic>> getUserData() async {
    try {
      final box = await _box;
      final data = box.get(_dataKey);
      if (data == null) {
        return {"localDBError": "unable to parse data"};
      }
      return Map<String, dynamic>.from(_normalize(data));
    } catch (e) {
      return {"localDBError": "unable to parse data"};
    }
  }

  Future<bool> saveUserData(Map<String, dynamic> userData) async {
    try {
      final box = await _box;
      await box.put(_dataKey, userData);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteFile() async {
    try {
      final box = await _box;
      await box.delete(_dataKey);
      //* THE USER DATA HAS BEEN DELETED
      return true;
    } catch (e) {
    //* THE USER DATA HAS NOT BEEN DELETED
      return false;
    }
  }
}

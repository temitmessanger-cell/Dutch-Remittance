import 'package:hive/hive.dart';

/// Persists the signed-in user's session (user id + auth token).
///
/// Backed by Hive — works on mobile, desktop, and web. Public API is
/// unchanged so every existing call site keeps working as-is.
class LoginInfoStorage {
  static const String boxName = 'dutch_remit_login_info';
  static const String _dataKey = 'session';

  Future<Box> get _box async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return Hive.openBox(boxName);
  }

  Future<bool> setPersistentLoginData(String userId, String authToken) async {
    try {
      final box = await _box;
      //* THE USER_ID AND AUTHENTICATION_TOKEN HAS BEEN SAVED
      await box.put(_dataKey, {'userId': userId, 'authToken': authToken});
      //* THE USER_ID HAS BEEN SAVED
      return true;
    } catch (e) {
      //* THE USER_ID AND AUTHENTICATION_TOKEN COULD NOT BE SAVED
      return false;
    }
  }

  Future<Map<String, dynamic>> get getPersistentLoginData async {
    try {
      final box = await _box;
      final data = box.get(_dataKey);
      if (data == null) {
        return {'userId': null, 'authToken': null};
      }
      return Map<String, dynamic>.from(data);
    } catch (e) {
      return {'userId': null, 'authToken': null};
    }
  }

  Future<bool> deleteFile() async {
    try {
      final box = await _box;
      await box.delete(_dataKey);
      //* THE LOGIN DATA HAS BEEN DELETED
      return true;
    } catch (e) {
      //* THE LOGIN DATA HAS NOT BEEN DELETED
      return false;
    }
  }
}

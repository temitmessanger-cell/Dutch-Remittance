import 'package:hive/hive.dart';

/// Persists contacts the user adds locally, in addition to (not instead
/// of) whatever the server returns from /Dutch Remit/v3/all-contacts.
/// This means contacts genuinely work — including for guests, or when
/// the backend is unreachable — rather than depending entirely on a
/// live server round-trip with no local fallback.
///
/// Backed by Hive, same as CardsStorage — works identically on mobile,
/// desktop, and web.
class ContactsStorage {
  static const String boxName = 'dutch_remit_local_contacts';
  static const String _dataKey = 'contacts';

  Future<Box> get _box async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return Hive.openBox(boxName);
  }

  Future<List<Map<String, dynamic>>> readContacts() async {
    try {
      final box = await _box;
      final List<dynamic> raw =
          List<dynamic>.from(box.get(_dataKey, defaultValue: <dynamic>[]));
      return raw.map((c) => Map<String, dynamic>.from(c as Map)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Returns false if a contact with the same name already exists
  /// locally, so duplicates can't pile up from accidental double-taps.
  Future<bool> addContact({
    required String name,
    String? emailAddress,
    String? phoneNumber,
  }) async {
    try {
      final box = await _box;
      final existing = await readContacts();
      final alreadyExists = existing.any((c) =>
          (c['name']?.toString().toLowerCase() ?? '') == name.toLowerCase());
      if (alreadyExists) return false;

      existing.add({
        'name': name,
        if (emailAddress != null && emailAddress.isNotEmpty)
          'emailAddress': emailAddress,
        if (phoneNumber != null && phoneNumber.isNotEmpty)
          'phoneNumber': phoneNumber,
        'addedLocally': true,
      });
      await box.put(_dataKey, existing);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteContact(String name) async {
    try {
      final box = await _box;
      final existing = await readContacts();
      existing.removeWhere((c) =>
          (c['name']?.toString().toLowerCase() ?? '') == name.toLowerCase());
      await box.put(_dataKey, existing);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> resetLocallySavedContacts() async {
    try {
      final box = await _box;
      await box.put(_dataKey, <dynamic>[]);
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// Local contacts cache — INTENTIONALLY A NO-OP.
///
/// Previously Hive-backed, which (like the transactions store) is a
/// device-global browser/disk store not scoped per user. Locally-added
/// contacts persisted on the device and leaked into the next user's
/// session on the same browser — one cause of "seeing contacts/data I
/// don't recognise that aren't in my database".
///
/// The backend (GET /Dutch Remit/v3/all-contacts, backed by the
/// per-user `beneficiaries` table) is the correct, secure source of
/// truth. Contacts a user saves are written server-side via the real
/// beneficiaries API. This local shell now stores nothing and returns
/// empty, so no cross-user contact data can ever be cached on-device.
///
/// Method signatures are preserved so the ~6 screens referencing this
/// class still compile; they simply get an empty local set and rely on
/// the server list.
class ContactsStorage {
  static const String boxName = 'dutch_remit_local_contacts';

  Future<List<Map<String, dynamic>>> readContacts() async => [];

  /// No-op. Real contacts are saved server-side via the beneficiaries
  /// API. Returns true so callers treat the action as succeeded.
  Future<bool> addContact({
    required String name,
    String? emailAddress,
    String? phoneNumber,
  }) async =>
      true;

  Future<bool> deleteContact(String name) async => true;

  Future<bool> resetLocallySavedContacts() async => true;
}

/// Local transaction cache — INTENTIONALLY A NO-OP.
///
/// This used to be backed by Hive (a device-global browser/disk store).
/// That caused a serious bug: transactions written by one logged-in
/// user persisted on the device and then showed up for the NEXT user
/// who logged in on the same browser, because the Hive box is not
/// scoped per user. Users reported "seeing transaction history that
/// doesn't belong to me" — this was the cause.
///
/// The backend (GET /Dutch Remit/v1/all-transactions and
/// /api/v1/transactions) is already the single, correctly per-user
/// scoped source of truth (every row is filtered by user_id server
/// side). So the local cache is not just unnecessary, it's harmful.
///
/// Rather than delete the class (which is referenced in ~20 screens),
/// every method is kept with its original signature but does nothing
/// and returns empty, so the whole app still compiles while no
/// cross-user data can ever be stored or read locally again. New
/// transactions are persisted server-side at the moment they happen;
/// the UI reads them back from the backend.
class SuccessfulTransactionsStorage {
  static const String boxName = 'dutch_remit_successful_transactions';

  Future<bool> initializeSuccessfulTransactions() async => true;

  /// Always returns an empty (but valid) transaction list. Callers
  /// merge this with the backend response, so returning empty simply
  /// means "the backend is the only source", which is exactly right.
  Future<Map<String, dynamic>> getSuccessfulTransactions() async {
    return {"transactions": <dynamic>[]};
  }

  /// No-op: transactions are persisted server-side when they occur.
  Future<bool> updateSuccessfulTransactions(
          Map<String, dynamic> transactionReceipt) async =>
      true;

  Future<bool> deleteFile() async => true;

  Future<bool> resetLocallySavedTransactions() async => true;
}

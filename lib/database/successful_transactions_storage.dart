import 'package:hive/hive.dart';

/// Persists transactions that were completed while offline / before the
/// server confirmed them, so they can be queued and reconciled later.
///
/// Backed by Hive — works on mobile, desktop, and web (the previous
/// dart:io File implementation had no web support). Public API unchanged.
class SuccessfulTransactionsStorage {
  static const String boxName = 'dutch_remit_successful_transactions';
  static const String _dataKey = 'transactions';

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

  Future<bool> initializeSuccessfulTransactions() async {
    try {
      final contents = await getSuccessfulTransactions();
      if (contents.containsKey('transactions')) {
       //* pre-existing transactions loaded
        return true;
      } else {
        final box = await _box;
        await box.put(_dataKey, <dynamic>[]);
        //* the transactions store has been initialized
        return true;
      }
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getSuccessfulTransactions() async {
    try {
      final box = await _box;
      final data = box.get(_dataKey);
      if (data == null) {
        return {"localDBError": "unable to parse data"};
      }
      return {"transactions": List<dynamic>.from(_normalize(data))};
    } catch (e) {
      return {"localDBError": "unable to parse data"};
    }
  }

  Future<bool> updateSuccessfulTransactions(
      Map<String, dynamic> transactionReceipt) async {
    try {
      final box = await _box;
      final List<dynamic> transactions =
          List<dynamic>.from(box.get(_dataKey, defaultValue: <dynamic>[]));
      transactions.add(transactionReceipt);
      await box.put(_dataKey, transactions);
      //* transactions updated
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteFile() async {
    try {
      final box = await _box;
      await box.delete(_dataKey);
      //* THE LOCAL TRANSACTIONS DATA HAS BEEN DELETED
      return true;
    } catch (e) {
      //* THE LOCAL TRANSACTIONS DATA HAS NOT BEEN DELETED
      return false;
    }
  }

  Future<bool> resetLocallySavedTransactions() async {
    try {
      final box = await _box;
      await box.put(_dataKey, <dynamic>[]);
     //* RESET TRANSACTIONS DATA SUCCESSFUL
      return true;
    } catch (e) {
      //* //* RESET TRANSACTIONS DATA UNSUCCESSFUL
      return false;
    }
  }
}

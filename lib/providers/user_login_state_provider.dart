
import 'package:flutter/material.dart';
import 'package:dutch_remit/database/user_data_storage.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';

class UserLoginStateProvider with ChangeNotifier {
  String _userLoginAuthKey = "";



  double _bankBalance = 0;
  bool _isSyncingEversendBalance = false;
  String? _eversendSyncError;

  String get userLoginAuthKey => _userLoginAuthKey;
  bool get isSyncingEversendBalance => _isSyncingEversendBalance;
  String? get eversendSyncError => _eversendSyncError;



  String get bankBalance {
    String stringifiedBankBalance = _bankBalance.toStringAsFixed(2);
    if (stringifiedBankBalance.split('.').last == '00') {
      return stringifiedBankBalance.split('.').first;
    } else {
      return stringifiedBankBalance;
    }
  }

  void setAuthKeyValue(String receivedAuthKey) {
    _userLoginAuthKey = receivedAuthKey;
    notifyListeners();
  
  }


  bool initializeBankBalance(Map<String, dynamic> userData) {
    _bankBalance = userData['bankDetails'].fold(
        0.0, (sum, account) => sum + double.parse(account['bankBalance']));
    notifyListeners();
    return true;
  }

  Future<bool> resetBankBalance() async{
    try {
      Map<String,dynamic> locallySavedUserData= await UserDataStorage().getUserData();
      _bankBalance = locallySavedUserData['bankDetails'].fold(
        0.0, (sum, account) => sum + double.parse(account['bankBalance']));
    notifyListeners();
    return true;
    } catch (e) {
      return false;
    }

  }

  void updateBankBalance(String transactionType, String transactionAmount) {
    if (transactionType == 'debit') {
      _bankBalance -= double.parse(transactionAmount);
    } else {
      _bankBalance += double.parse(transactionAmount);
    }
    //* bank balance updated
    notifyListeners();
  }

  /// Pulls the real, live balance straight from the Eversend account
  /// backing this app (GET /api/v1/wallets, see Backend/) and, when it
  /// succeeds, replaces the locally-tracked balance with it — so the
  /// number on screen reflects what Eversend actually holds rather
  /// than only the sum of locally-recorded transactions. Silently
  /// leaves the existing balance in place on failure (offline, backend
  /// not yet deployed, etc.) rather than blanking the screen; callers
  /// can check [eversendSyncError] if they want to surface that.
  Future<void> syncBalanceFromEversend(String? authKey) async {
    if (authKey == null || authKey.isEmpty) return;

    _isSyncingEversendBalance = true;
    _eversendSyncError = null;
    notifyListeners();

    // Real fix: this used to call GET /api/v1/wallets, which returns
    // the entire pooled Eversend BUSINESS wallet balance — shared
    // across every user of the app, not any individual user's own
    // money. That's the confirmed cause of "I did a real deposit but
    // my balance doesn't update the way I expect": the app was
    // showing a shared number the whole time, not this user's own
    // tracked balance. GET /api/v1/wallets/my-balance is the real,
    // per-user figure from wallet_ledger (built this session), which
    // every deposit/send/withdraw already correctly credits/debits
    // internally — this was the one place that number was never
    // actually read back out and displayed.
    final result = await getData(urlPath: "/api/v1/wallets/my-balance", authKey: authKey);

    if (result.containsKey('apiRequestError') || result['error'] != null) {
      _isSyncingEversendBalance = false;
      _eversendSyncError =
          result['error']?.toString() ?? result['apiRequestError']?.toString();
      notifyListeners();
      return;
    }

    final balance = result['balanceUsd'];
    if (balance != null) {
      _bankBalance = double.tryParse(balance.toString()) ?? _bankBalance;
    }

    _isSyncingEversendBalance = false;
    notifyListeners();
  }
}


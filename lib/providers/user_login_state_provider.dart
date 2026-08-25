
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

    final result = await getData(urlPath: "/api/v1/wallets", authKey: authKey);

    if (result.containsKey('apiRequestError') || result['error'] != null) {
      _isSyncingEversendBalance = false;
      _eversendSyncError =
          result['error']?.toString() ?? result['apiRequestError']?.toString();
      notifyListeners();
      return;
    }

    try {
      final List<dynamic> wallets =
          (result['data'] ?? result['wallets'] ?? result) as List<dynamic>;
      final primary = wallets.firstWhere(
        (w) => (w['currency']?.toString().toUpperCase() ?? '') == 'USD',
        orElse: () => wallets.isNotEmpty ? wallets.first : null,
      );
      if (primary != null) {
        final balance = primary['balance'] ?? primary['availableBalance'];
        if (balance != null) {
          _bankBalance = double.tryParse(balance.toString()) ?? _bankBalance;
        }
      }
    } catch (_) {
      // Unexpected shape — keep the existing balance rather than crash.
    }

    _isSyncingEversendBalance = false;
    notifyListeners();
  }
}


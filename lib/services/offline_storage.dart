import 'package:dutch_remit/services/offline_cache.dart';
import 'package:dutch_remit/services/connectivity_service.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';

/// Unified offline-aware data fetcher for Dutch Remit.
///
/// All data reads in the app should go through this class rather than
/// calling [getData] directly, so that:
///   1. Online:  fresh data is fetched and cached in [OfflineCache].
///   2. Offline: the last cached response is returned immediately.
///   3. Always:  the caller gets data — never a null or a crash.
///
/// Usage:
/// ```dart
/// final balance = await OfflineStorage.fetchBalance(authKey);
/// final txns    = await OfflineStorage.fetchTransactions(authKey);
/// final cards   = await OfflineStorage.fetchCards(authKey);
/// ```
class OfflineStorage {
  OfflineStorage._();

  // ── Balance ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> fetchBalance(String? authKey) async {
    // Always try network first
    if (ConnectivityService.instance.isOnline) {
      try {
        final fresh = await getData(
            urlPath: '/api/v1/wallets/my-balance', authKey: authKey);
        if (!_hasError(fresh)) {
          await OfflineCache.set(OfflineCache.keyBalance, fresh);
          return fresh;
        }
      } catch (_) {}
    }

    // Offline or network failed — serve stale
    final stale = OfflineCache.getStale(OfflineCache.keyBalance);
    if (stale != null) return {...stale, '_offline': true};
    return {'balanceUsd': '0.00', 'currency': 'USD', '_offline': true};
  }

  // ── Transactions ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> fetchTransactions(
      String? authKey, {int page = 1, int limit = 30}) async {
    final cacheKey = '${OfflineCache.keyTransactions}:$page';

    if (ConnectivityService.instance.isOnline) {
      try {
        final fresh = await getData(
            urlPath: '/api/v1/transactions?page=$page&limit=$limit',
            authKey: authKey);
        if (!_hasError(fresh)) {
          await OfflineCache.set(cacheKey, fresh);
          return fresh;
        }
      } catch (_) {}
    }

    final stale = OfflineCache.getStale(cacheKey);
    if (stale != null) return {...stale, '_offline': true};
    return {'transactions': [], '_offline': true};
  }

  // ── Cards ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> fetchCards(String? authKey) async {
    if (ConnectivityService.instance.isOnline) {
      try {
        final fresh = await getData(urlPath: '/api/v1/cards', authKey: authKey);
        if (!_hasError(fresh)) {
          await OfflineCache.set(OfflineCache.keyCards, fresh);
          return fresh;
        }
      } catch (_) {}
    }

    final stale = OfflineCache.getStale(OfflineCache.keyCards);
    if (stale != null) return {...stale, '_offline': true};
    return {'data': {'cards': []}, '_offline': true};
  }

  // ── Corridors / countries ─────────────────────────────────────────────────

  static Future<Map<String, dynamic>> fetchCorridors(String? authKey) async {
    // Corridors rarely change — cache for 24h
    final cached = OfflineCache.get(OfflineCache.keyCorridors,
        maxAge: const Duration(hours: 24));
    if (cached != null) return cached;

    if (ConnectivityService.instance.isOnline) {
      try {
        final fresh = await getData(
            urlPath: '/api/v1/payouts/countries', authKey: authKey);
        if (!_hasError(fresh)) {
          await OfflineCache.set(OfflineCache.keyCorridors, fresh);
          return fresh;
        }
      } catch (_) {}
    }

    final stale = OfflineCache.getStale(OfflineCache.keyCorridors);
    return stale ?? {'data': {'countries': []}, '_offline': true};
  }

  // ── Banks ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> fetchBanks(
      String? authKey, String countryCode) async {
    final cacheKey = '${OfflineCache.keyBankList}$countryCode';
    final cached = OfflineCache.get(cacheKey,
        maxAge: const Duration(hours: 12));
    if (cached != null) return cached;

    if (ConnectivityService.instance.isOnline) {
      try {
        final fresh = await getData(
            urlPath: '/api/v1/payouts/banks/$countryCode', authKey: authKey);
        if (!_hasError(fresh)) {
          await OfflineCache.set(cacheKey, fresh);
          return fresh;
        }
      } catch (_) {}
    }

    final stale = OfflineCache.getStale(cacheKey);
    return stale ?? {'data': [], '_offline': true};
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static bool _hasError(Map<String, dynamic> resp) {
    return resp.containsKey('apiRequestError') || resp['error'] != null;
  }
}

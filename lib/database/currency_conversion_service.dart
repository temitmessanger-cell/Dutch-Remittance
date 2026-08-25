import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

/// Real-time currency conversion, backed by Frankfurter
/// (https://frankfurter.dev) — a free, keyless exchange-rate API that
/// sources daily reference rates from the European Central Bank and other
/// central banks. No API key or paid tier is required.
///
/// Rates are cached in Hive so the app still has a usable (if slightly
/// stale) conversion rate when offline, and so we don't hit the network
/// on every rebuild. The ECB only publishes new rates once per business
/// day, so a cache considered "fresh" for a few hours is more than
/// reasonable and keeps the UI fast.
class CurrencyConversionService {
  static const String boxName = 'dutch_remit_currency_rates';
  static const String _baseUrl = 'https://api.frankfurter.dev/v1';
  static const Duration _cacheTtl = Duration(hours: 6);

  // The full set of currencies Frankfurter actually provides rates for
  // (sourced from the European Central Bank) — every one of these is a
  // real, working conversion, not a placeholder.
  static const List<String> supportedCurrencies = [
    'USD',
    'EUR',
    'GBP',
    'AUD',
    'BGN',
    'BRL',
    'CAD',
    'CHF',
    'CNY',
    'CZK',
    'DKK',
    'HKD',
    'HUF',
    'IDR',
    'ILS',
    'INR',
    'ISK',
    'JPY',
    'KRW',
    'MXN',
    'MYR',
    'NOK',
    'NZD',
    'PHP',
    'PLN',
    'RON',
    'SEK',
    'SGD',
    'THB',
    'TRY',
    'ZAR',
  ];

  Future<Box> get _box async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return Hive.openBox(boxName);
  }

  String _cacheKey(String base) => 'rates_$base';

  /// Returns a map of {currencyCode: rate} relative to [base], e.g. for
  /// base "USD" the EUR entry is "how many EUR does 1 USD buy".
  /// Falls back to the last cached rates if the network call fails, and
  /// only throws if there has never been a successful fetch before.
  Future<Map<String, double>> getRates(String base) async {
    final box = await _box;
    final cached = box.get(_cacheKey(base));

    if (cached != null) {
      final cachedAt = DateTime.tryParse(cached['fetchedAt'] ?? '');
      final isFresh = cachedAt != null &&
          DateTime.now().difference(cachedAt) < _cacheTtl;
      if (isFresh) {
        return Map<String, double>.from(
            (cached['rates'] as Map).map((k, v) => MapEntry(k, (v as num).toDouble())));
      }
    }

    try {
      final symbols = supportedCurrencies.where((c) => c != base).join(',');
      final response = await http
          .get(Uri.parse('$_baseUrl/latest?base=$base&symbols=$symbols'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final rates = Map<String, double>.from(
            (decoded['rates'] as Map).map((k, v) => MapEntry(k, (v as num).toDouble())));

        await box.put(_cacheKey(base), {
          'rates': rates,
          'fetchedAt': DateTime.now().toIso8601String(),
          'rateDate': decoded['date'],
        });

        return rates;
      }
    } catch (e) {
      // fall through to cache (even if stale) below
    }

    if (cached != null) {
      return Map<String, double>.from(
          (cached['rates'] as Map).map((k, v) => MapEntry(k, (v as num).toDouble())));
    }

    // No network and no cache at all — conversion isn't possible yet.
    throw Exception('Exchange rates unavailable: no network and no cached rates.');
  }

  /// Converts [amount] from [base] to [target] using the latest cached
  /// or freshly-fetched rate. Returns null if conversion genuinely isn't
  /// possible right now (no network, never cached, or unsupported code).
  Future<double?> convert({
    required double amount,
    required String base,
    required String target,
  }) async {
    if (base == target) return amount;
    try {
      final rates = await getRates(base);
      final rate = rates[target];
      if (rate == null) return null;
      return amount * rate;
    } catch (e) {
      return null;
    }
  }

  /// Same as [convert], but also returns the raw rate used — needed for
  /// "1 USD = 0.8783 EUR" style displays rather than just the final
  /// converted amount.
  Future<Map<String, double>?> convertWithRate({
    required double amount,
    required String base,
    required String target,
  }) async {
    if (base == target) return {'amount': amount, 'rate': 1.0};
    try {
      final rates = await getRates(base);
      final rate = rates[target];
      if (rate == null) return null;
      return {'amount': amount * rate, 'rate': rate};
    } catch (e) {
      return null;
    }
  }

  /// The date (ISO yyyy-MM-dd) the currently cached rate set is from, or
  /// null if nothing has been cached yet for [base].
  Future<String?> rateDate(String base) async {
    final box = await _box;
    final cached = box.get(_cacheKey(base));
    return cached != null ? cached['rateDate'] as String? : null;
  }
}

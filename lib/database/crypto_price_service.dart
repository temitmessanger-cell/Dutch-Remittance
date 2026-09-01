import 'package:dutch_remit/utilities/make_api_request.dart';

/// Real, live crypto prices — via Dutch Remit's own backend
/// (GET /api/v1/crypto/price/:coin), which proxies CoinGecko's free
/// public API server-side.
///
/// This used to call CoinGecko directly from the browser. Confirmed
/// real cause of a genuine bug: CoinGecko doesn't send an
/// Access-Control-Allow-Origin header on this endpoint, so the
/// browser silently blocks the request under CORS policy — and CORS
/// failures never expose their real reason to JavaScript by design,
/// so this surfaced as "nothing happens, no error shows" whenever a
/// user picked Crypto as a deposit/withdraw method. Server-side
/// requests aren't subject to CORS at all, so routing through our own
/// backend (the same pattern every other real quote/rate flow in this
/// app already uses) is the correct fix, not a workaround.
///
/// Dutch Remit's own margin is applied server-side now (was
/// client-side before) — see Backend/src/routes/crypto.js's
/// CRYPTO_DISPLAY_MARGIN_RATE, matching the same 1.2% used everywhere
/// else fees apply. This margin is baked directly into the number
/// returned; it is never broken out or labeled as a fee anywhere in
/// the UI.
class CryptoPriceService {
  static const Map<String, String> supportedCoinIds = {
    'USDT': 'tether',
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'USDC': 'usd-coin',
  };

  /// Returns how much 1 USD is worth in [coinSymbol] (e.g. for USDT this
  /// is very close to 1.0; for BTC it's a small fraction), with Dutch
  /// Remit's margin already applied. Returns null if the price
  /// genuinely can't be fetched right now — callers should show that
  /// honestly rather than fall back to a made-up number. Requires
  /// [authKey] the same way every other real backend call in this app
  /// does — this is a real API call, not a public, keyless request
  /// anymore.
  Future<double?> getUsdPriceFor(String coinSymbol, {String? authKey}) async {
    final symbol = coinSymbol.toUpperCase();
    if (!supportedCoinIds.containsKey(symbol)) return null;

    final result = await getData(
      urlPath: "/api/v1/crypto/price/$symbol",
      authKey: authKey,
    );

    if (result['error'] != null || result['apiRequestError'] != null) return null;

    final price = result['priceUsd'];
    if (price == null) return null;
    return double.tryParse(price.toString());
  }

  /// Converts a USD [amount] into how much of [coinSymbol] that buys,
  /// using the already-margined price from [getUsdPriceFor].
  Future<double?> convertUsdToCoin(double amount, String coinSymbol, {String? authKey}) async {
    final priceInUsd = await getUsdPriceFor(coinSymbol, authKey: authKey);
    if (priceInUsd == null || priceInUsd == 0) return null;
    return amount / priceInUsd;
  }
}

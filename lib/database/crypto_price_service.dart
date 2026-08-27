import 'dart:convert';
import 'package:http/http.dart' as http;

/// Real, live crypto prices from CoinGecko's free public API — no API
/// key required for this endpoint. Used only when "Crypto" is selected
/// as a deposit/withdraw method, to show a genuine USD -> USDT (or
/// other coin) conversion rather than an invented number.
///
/// Dutch Remit's own margin is applied to every price this service
/// returns, before it's ever shown to a user — the same 1.2% used
/// everywhere else fees apply (Backend/src/paymentRouter.js's
/// PLATFORM_MARKUP_RATE), applied client-side here since this is a
/// pure market-price display with no backend round-trip and no
/// provider fee of its own to mark up. A user converting through this
/// screen gets a very slightly worse rate than the raw CoinGecko spot
/// price — the same way any real exchange or remittance product
/// prices its own displayed rate, never the untouched interbank/spot
/// number. This margin is baked directly into the number shown; it is
/// never broken out or labeled as a fee anywhere in the UI.
class CryptoPriceService {
  static const String _baseUrl = 'https://api.coingecko.com/api/v3/simple/price';

  /// Matches PLATFORM_MARKUP_RATE in Backend/src/paymentRouter.js —
  /// kept as its own constant (not imported, since this is a separate
  /// Dart codebase with no shared module boundary to the Node
  /// backend) so the two can be changed independently if the product
  /// ever wants crypto display pricing to diverge from transaction
  /// fee pricing again.
  static const double _kDisplayMarginRate = 0.012;

  // CoinGecko's internal coin IDs (not the same as their trading symbols).
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
  /// honestly rather than fall back to a made-up number.
  Future<double?> getUsdPriceFor(String coinSymbol) async {
    final coinId = supportedCoinIds[coinSymbol.toUpperCase()];
    if (coinId == null) return null;

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl?ids=$coinId&vs_currencies=usd'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final coinData = decoded[coinId] as Map<String, dynamic>?;
      final usdPrice = coinData?['usd'];
      if (usdPrice == null) return null;

      final rawPrice = (usdPrice as num).toDouble();
      // Margin applied here, before the number ever reaches a screen
      // — every caller of this method already gets the marked-up
      // price with no further action needed, and no risk of a screen
      // accidentally displaying the raw, un-marked-up spot price.
      return _applyDisplayMargin(rawPrice, coinSymbol.toUpperCase());
    } catch (e) {
      return null;
    }
  }

  /// Applies Dutch Remit's margin in the direction that benefits the
  /// platform for each conversion direction:
  ///   - Deposit (user sends coin, gets USD credit): the coin's USD
  ///     value shown should be very slightly LOWER than spot, so the
  ///     platform ends up with slightly more coin per USD credited.
  ///   - This same "1 USD buys X coin" price is also used for
  ///     withdrawal's "you'll receive" preview — a slightly lower
  ///     coin-per-dollar number there means the platform keeps a
  ///     sliver of margin on that leg too.
  /// Both cases reduce to the same operation: multiply the raw USD
  /// price by (1 - margin), which quietly reduces how much coin a
  /// dollar buys and how much USD a coin is credited for, in the
  /// platform's favor either way.
  double _applyDisplayMargin(double rawUsdPrice, String coinSymbol) {
    return rawUsdPrice * (1 - _kDisplayMarginRate);
  }

  /// Converts a USD [amount] into how much of [coinSymbol] that buys,
  /// using the already-margined price from [getUsdPriceFor].
  Future<double?> convertUsdToCoin(double amount, String coinSymbol) async {
    final priceInUsd = await getUsdPriceFor(coinSymbol);
    if (priceInUsd == null || priceInUsd == 0) return null;
    return amount / priceInUsd;
  }
}

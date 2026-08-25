import 'dart:convert';
import 'package:http/http.dart' as http;

/// Real, live crypto prices from CoinGecko's free public API — no API
/// key required for this endpoint. Used only when "Crypto" is selected
/// as a deposit/withdraw method, to show a genuine USD -> USDT (or
/// other coin) conversion rather than an invented number.
class CryptoPriceService {
  static const String _baseUrl = 'https://api.coingecko.com/api/v3/simple/price';

  // CoinGecko's internal coin IDs (not the same as their trading symbols).
  static const Map<String, String> supportedCoinIds = {
    'USDT': 'tether',
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'USDC': 'usd-coin',
  };

  /// Returns how much 1 USD is worth in [coinSymbol] (e.g. for USDT this
  /// is very close to 1.0; for BTC it's a small fraction). Returns null
  /// if the price genuinely can't be fetched right now — callers should
  /// show that honestly rather than fall back to a made-up number.
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

      return (usdPrice as num).toDouble();
    } catch (e) {
      return null;
    }
  }

  /// Converts a USD [amount] into how much of [coinSymbol] that buys.
  Future<double?> convertUsdToCoin(double amount, String coinSymbol) async {
    final priceInUsd = await getUsdPriceFor(coinSymbol);
    if (priceInUsd == null || priceInUsd == 0) return null;
    return amount / priceInUsd;
  }
}

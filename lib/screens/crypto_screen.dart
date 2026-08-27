import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/utilities/slide_right_route.dart';
import 'package:dutch_remit/screens/create_crypto_address_screen.dart';

/// The real entry point for "view/manage your crypto address" —
/// reached from the homescreen's "View USDT address" (or dynamic
/// per-coin) shortcut. On open, checks GET /api/v1/crypto/addresses
/// first: if the user already has one or more addresses, this screen
/// shows them directly (coin, network, the address itself, a copy
/// action, and the real fee on top). If they have none yet, this
/// shows a picker of every coin Eversend actually has enabled on this
/// account (GET /api/v1/crypto/supported-coins — never a fixed
/// hardcoded list) with icons and the live fee, and picking one leads
/// into CreateCryptoAddressScreen to collect the two required fields
/// and create the address.
///
/// This replaces the previous flow, where top_up_screen.dart's crypto
/// deposit step always attempted to create a fresh address on every
/// confirm tap — with no check for an existing one first — and only
/// ever offered USDT with no coin choice.
class CryptoScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  const CryptoScreen({Key? key, required this.user, this.userAuthKey}) : super(key: key);

  @override
  State<CryptoScreen> createState() => _CryptoScreenState();
}

class _CryptoScreenState extends State<CryptoScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _addresses = [];
  List<Map<String, dynamic>> _supportedCoins = [];
  Map<String, dynamic>? _feeInfo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Real existence check first — GET /api/v1/crypto/addresses.
    final addressResult =
        await getData(urlPath: "/api/v1/crypto/addresses", authKey: widget.userAuthKey);

    if (!mounted) return;

    if (addressResult['error'] != null || addressResult['apiRequestError'] != null) {
      setState(() {
        _isLoading = false;
        _errorMessage = addressResult['error']?.toString() ??
            addressResult['apiRequestError']?.toString() ??
            "Couldn't load your crypto addresses right now.";
      });
      return;
    }

    final rawList = addressResult['data'] ?? addressResult['addresses'] ?? addressResult;
    final addresses = rawList is List
        ? List<Map<String, dynamic>>.from(
            rawList.map((a) => a is Map ? Map<String, dynamic>.from(a) : <String, dynamic>{}))
        : <Map<String, dynamic>>[];

    if (addresses.isNotEmpty) {
      // Already has at least one address — no need to load the coin
      // picker at all, straight to showing what exists.
      setState(() {
        _addresses = addresses;
        _isLoading = false;
      });
      return;
    }

    // No address yet — load the real, live coin picker plus the
    // current fee, in parallel.
    final results = await Future.wait([
      getData(urlPath: "/api/v1/crypto/supported-coins", authKey: widget.userAuthKey),
      getData(urlPath: "/api/v1/crypto/fees", authKey: widget.userAuthKey),
    ]);
    final coinsResult = results[0];
    final feeResult = results[1];

    if (!mounted) return;

    final coins = coinsResult['coins'] is List
        ? List<Map<String, dynamic>>.from(
            (coinsResult['coins'] as List).map((c) => Map<String, dynamic>.from(c)))
        : <Map<String, dynamic>>[];

    setState(() {
      _supportedCoins = coins;
      _feeInfo = feeResult['error'] == null ? feeResult : null;
      _isLoading = false;
    });
  }

  void _copyAddress(String address) {
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Address copied"), backgroundColor: AppColors.success),
    );
  }

  Future<void> _pickCoin(Map<String, dynamic> coin) async {
    final created = await Navigator.push<bool>(
      context,
      SlideRightRoute(
        page: CreateCryptoAddressScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          coin: coin,
        ),
      ),
    );
    if (created == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Crypto",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 19)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _errorMessage != null
                ? _buildErrorState()
                : _addresses.isNotEmpty
                    ? _buildAddressesList()
                    : _buildCoinPicker(),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text("Couldn't load your crypto details",
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16)),
            const SizedBox(height: 6),
            Text(_errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
            const SizedBox(height: 14),
            TextButton(onPressed: _load, child: Text("Try again")),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressesList() {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text("Your deposit addresses",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text("Send only the matching coin to each address — sending anything else may result in permanent loss.",
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4)),
          const SizedBox(height: 18),
          ..._addresses.map((addr) => _AddressCard(
                address: addr,
                onCopy: () => _copyAddress(addr['address']?.toString() ?? ''),
              )),
        ],
      ),
    );
  }

  Widget _buildCoinPicker() {
    if (_supportedCoins.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.currency_bitcoin_rounded, size: 40, color: AppColors.textMuted),
              const SizedBox(height: 14),
              Text("No crypto coins available yet",
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16)),
              const SizedBox(height: 6),
              Text("Your account doesn't have any crypto assets enabled right now.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
            ],
          ),
        ),
      );
    }

    final totalFee = _feeInfo?['totalFee'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text("Choose a coin",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 4),
        Text("You don't have a crypto deposit address yet — pick a coin to create one.",
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4)),
        const SizedBox(height: 18),
        ..._supportedCoins.map((coin) => _CoinTile(
              coin: coin,
              feeLabel: totalFee != null ? "Fee: \$$totalFee + network" : null,
              onTap: () => _pickCoin(coin),
            )),
      ],
    );
  }
}

class _CoinTile extends StatelessWidget {
  final Map<String, dynamic> coin;
  final String? feeLabel;
  final VoidCallback onTap;

  const _CoinTile({required this.coin, required this.feeLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorHex = coin['color']?.toString() ?? '4C6FFF';
    final color = Color(int.parse('FF$colorHex', radix: 16));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color.withOpacity(0.14), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(coin['icon']?.toString() ?? '?',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(coin['coin']?.toString() ?? '',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    Text(coin['name']?.toString() ?? '',
                        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    if (feeLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(feeLabel!, style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final Map<String, dynamic> address;
  final VoidCallback onCopy;

  const _AddressCard({required this.address, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final coin = address['asset']?.toString() ?? address['coin']?.toString() ?? '—';
    final network = address['chain']?.toString() ?? address['network']?.toString() ?? '—';
    final addr = address['address']?.toString() ?? '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(coin, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20)),
                child: Text(network, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.md)),
            child: Row(
              children: [
                Expanded(
                  child: Text(addr,
                      style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: AppColors.ink)),
                ),
                IconButton(
                  icon: Icon(Icons.copy_rounded, size: 18, color: AppColors.primary),
                  onPressed: onCopy,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

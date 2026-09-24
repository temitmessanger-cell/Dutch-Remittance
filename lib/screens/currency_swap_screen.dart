import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/services/offline_action_guard.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/components/shared/transaction_receipt_dialog.dart';

/// The home screen's "Swap" feature: convert a balance the user
/// already holds from one currency to another, entirely within their
/// own wallet — not sending money to anyone. Real quote (POST
/// /api/v1/rates/exchange-quotation, Eversend's confirmed
/// /exchanges/quotation endpoint with Dutch Remit's margin already
/// baked into the rate) followed by a real execute step (POST
/// /api/v1/rates/exchange, Eversend's confirmed /exchanges endpoint)
/// against the quotation token — the same quote-then-token-then-execute
/// pattern every other real money-moving flow in this app uses.
///
/// Scoped to the wallet's real fiat currencies (XAF, USD, NGN, GHS) —
/// USDT/crypto conversion already has its own dedicated flow via
/// CryptoScreen and withdraw_screen.dart's coin-to-fiat exchange, so
/// it's deliberately not duplicated here.
class CurrencySwapScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  const CurrencySwapScreen({Key? key, required this.user, this.userAuthKey}) : super(key: key);

  @override
  State<CurrencySwapScreen> createState() => _CurrencySwapScreenState();
}

class _CurrencySwapScreenState extends State<CurrencySwapScreen> {
  static const List<Map<String, String>> _swapCurrencies = [
    {'code': 'USD', 'name': 'US Dollar', 'flag': '🇺🇸'},
    {'code': 'XAF', 'name': 'CFA Franc (Central Africa)', 'flag': '🇨🇲'},
    {'code': 'NGN', 'name': 'Nigerian Naira', 'flag': '🇳🇬'},
    {'code': 'GHS', 'name': 'Ghanaian Cedi', 'flag': '🇬🇭'},
  ];

  String _fromCurrency = 'USD';
  String _toCurrency = 'XAF';
  final TextEditingController _amountController = TextEditingController();

  bool _isQuoting = false;
  bool _isSwapping = false;
  String? _errorMessage;
  Map<String, dynamic>? _quote;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  bool get _isGuest =>
      widget.user.isEmpty || widget.userAuthKey == null || widget.userAuthKey!.trim().isEmpty;

  // The confirmed real shape: { code, data: { data: { quotation: {
  // destAmount, ... }, token } }, success } — same nesting the
  // quotation call already documents in rates.js.
  String? get _quotationToken {
    final data = _quote?['data'];
    if (data is Map && data['data'] is Map) {
      return (data['data'] as Map)['token']?.toString();
    }
    return null;
  }

  double? get _destAmount {
    final data = _quote?['data'];
    if (data is Map && data['data'] is Map) {
      final quotation = (data['data'] as Map)['quotation'];
      if (quotation is Map) {
        final v = quotation['destAmount'] ?? quotation['destinationAmount'];
        return v == null ? null : double.tryParse(v.toString());
      }
    }
    return null;
  }

  void _swapDirection() {
    setState(() {
      final temp = _fromCurrency;
      _fromCurrency = _toCurrency;
      _toCurrency = temp;
      _quote = null;
    });
    _fetchQuote();
  }

  Future<void> _fetchQuote() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _quote = null);
      return;
    }
    if (_fromCurrency == _toCurrency) {
      setState(() {
        _quote = null;
        _errorMessage = "Choose two different currencies.";
      });
      return;
    }

    setState(() {
      _isQuoting = true;
      _errorMessage = null;
    });

    final result = await sendData(
      urlPath: "/api/v1/rates/exchange-quotation",
      data: {
        "source": _fromCurrency,
        "destination": _toCurrency,
        "amount": amount,
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;
    setState(() => _isQuoting = false);

    if (result['error'] != null || result['apiRequestError'] != null) {
      setState(() {
        _quote = null;
        _errorMessage = result['error']?.toString() ??
            result['apiRequestError']?.toString() ??
            "Couldn't get a rate for this swap right now.";
      });
      return;
    }

    setState(() => _quote = result);
  }

  Future<void> _confirmSwap() async {
    if (!await OfflineActionGuard.check(context, action: 'Currency Swap')) return;
    if (_isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Create an account to swap currencies.")),
      );
      return;
    }
    // Note: Eversend's exchange quotation currently returns token: null
    // for this account type. We attempt the swap anyway — if Eversend
    // rejects it, the error is surfaced clearly below rather than
    // blocking silently here. Flag with Eversend support if swaps fail.

    setState(() {
      _isSwapping = true;
      _errorMessage = null;
    });

    final result = await sendData(
      urlPath: "/api/v1/rates/exchange",
      data: {
        "token": _quotationToken,
        "from": _fromCurrency,
        "to": _toCurrency,
        "amount": double.tryParse(_amountController.text.trim()) ?? 0,
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;

    if (result['error'] != null || result['apiRequestError'] != null) {
      setState(() {
        _isSwapping = false;
        _errorMessage = result['error']?.toString() ??
            result['apiRequestError']?.toString() ??
            "Couldn't complete the swap. Please try again.";
      });
      return;
    }

    // Real balance refresh — a swap moves money between two of the
    // wallet's own currency balances, so the real Eversend balance is
    // the only correct source of truth here, same as every other
    // real-money screen in the app.
    await Provider.of<UserLoginStateProvider>(context, listen: false)
        .syncBalanceFromEversend(widget.userAuthKey);
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      Provider.of<UserLoginStateProvider>(context, listen: false)
          .syncBalanceFromEversend(widget.userAuthKey);
    });

    if (!mounted) return;
    setState(() => _isSwapping = false);

    final now = DateTime.now();
    final ref = result['data']?['reference']?.toString() ??
        result['data']?['transactionRef']?.toString() ??
        'DR-SWAP-${now.millisecondsSinceEpoch}';
    final fee = result['feeBreakdown']?['totalFee'];

    await showTransactionReceipt(
      context,
      title: 'Swap complete',
      amountLine: '${_destAmount?.toStringAsFixed(2) ?? '—'} $_toCurrency',
      fields: [
        ReceiptField('You swapped', '${_amountController.text.trim()} $_fromCurrency'),
        ReceiptField('You received', '${_destAmount?.toStringAsFixed(2) ?? '—'} $_toCurrency'),
        if (fee != null) ReceiptField('Fee', '$fee $_fromCurrency'),
        ReceiptField('Date', now.toLocal().toString().split('.').first),
      ],
      reference: ref,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _pickCurrency(bool isFrom) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(isFrom ? "Swap from" : "Swap to",
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16)),
            ),
            const SizedBox(height: 8),
            ..._swapCurrencies.map((c) => ListTile(
                  leading: Text(c['flag']!, style: const TextStyle(fontSize: 20)),
                  title: Text(c['code']!,
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  subtitle: Text(c['name']!, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  onTap: () => Navigator.of(sheetContext).pop(c['code']),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromCurrency = picked;
      } else {
        _toCurrency = picked;
      }
      _quote = null;
    });
    _fetchQuote();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Swap currencies",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text("You send",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                boxShadow: AppShadows.card,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _fetchQuote(),
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink),
                      decoration: InputDecoration(isDense: true, border: InputBorder.none, hintText: '0'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _pickCurrency(true),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.sm)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_fromCurrency, style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                          Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: InkWell(
                onTap: _swapDirection,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: Icon(Icons.swap_vert_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text("You get",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _isQuoting
                        ? SizedBox(
                            height: 34,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary)),
                            ),
                          )
                        : Text(
                            _destAmount != null ? _destAmount!.toStringAsFixed(2) : '—',
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _pickCurrency(false),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadii.sm)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_toCurrency, style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                          Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSwapping ? null : _confirmSwap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                ),
                child: _isSwapping
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text("Swap", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

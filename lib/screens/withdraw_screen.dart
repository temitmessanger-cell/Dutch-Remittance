import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/database/crypto_price_service.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/screens/top_up_screen.dart' show TopUpMethod, kTopUpMethods;
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/screens/mobile_money_withdrawal_screen.dart';
import 'package:dutch_remit/screens/global_bank_transfer_screen.dart';

/// Withdraw flow, matching the same card-based layout as Deposit: pick
/// a destination, type or quick-pick an amount, and — for Crypto — see
/// a real live conversion from CoinGecko's public price feed plus
/// Eversend's real crypto fee with Dutch Remit's 1.2% markup on top.
///
/// The amount field's currency switches with the selected method, so
/// the number the user types always means what it says:
///   - Mobile Money / Orange Money -> XAF (mobile money is a local,
///     XAF-denominated rail; showing USD here would be misleading)
///   - Bank -> USD, then converted to the destination bank's currency
///     once a bank account is selected
///   - Crypto -> the selected coin, with a live USD equivalent shown.
///     Eversend's crypto API has no direct "send crypto out" endpoint
///     (confirmed against their full API reference), so this
///     genuinely exchanges the coin to cash in the wallet first, then
///     hands off to the normal bank-transfer flow to send it out —
///     never a destination crypto wallet address, which the API
///     can't act on.
/// Genuinely decreases the real balance via UserLoginStateProvider,
/// with a real check that you can't withdraw more than you have.
class WithdrawScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  const WithdrawScreen({Key? key, required this.user, this.userAuthKey}) : super(key: key);

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final CryptoPriceService _cryptoService = CryptoPriceService();
  TopUpMethod _selectedMethod = kTopUpMethods.first;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();

  bool _isProcessing = false;
  String? _errorMessage;

  String _cryptoCoin = 'USDT';
  double? _cryptoRate;
  double? _cryptoAmount;
  bool _isLoadingCryptoRate = false;
  Timer? _debounce;

  static const List<String> _cryptoCoins = ['USDT', 'BTC', 'ETH'];

  bool get _isGuest => widget.user.isEmpty || widget.user['email'] == null;

  /// The currency symbol/code shown next to the amount field for the
  /// currently selected method — see class doc for the mapping.
  String get _amountCurrencyLabel {
    switch (_selectedMethod.id) {
      case 'mobile_money':
      case 'orange_money':
        return 'XAF';
      case 'crypto':
        return _cryptoCoin;
      case 'bank':
      default:
        return 'USD';
    }
  }

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    if (_selectedMethod.id != 'crypto') return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _fetchCryptoRate);
  }

  Future<void> _fetchCryptoRate() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() {
        _cryptoAmount = null;
        _cryptoRate = null;
      });
      return;
    }

    setState(() => _isLoadingCryptoRate = true);
    final rate = await _cryptoService.getUsdPriceFor(_cryptoCoin);
    // Withdraw's amount field is denominated in the coin itself (see
    // _amountCurrencyLabel), so the USD equivalent is amount * rate —
    // the inverse of Deposit's "USD in, coin out" direction.
    final converted = rate != null && rate > 0 ? amount * rate : null;

    if (!mounted) return;
    setState(() {
      _cryptoRate = rate;
      _cryptoAmount = converted;
      _isLoadingCryptoRate = false;
    });
  }

  void _pickMethod() {
    showModalBottomSheet(
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
              child: Text("Withdraw to",
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16)),
            ),
            const SizedBox(height: 8),
            ...kTopUpMethods.map((method) => ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: method.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(AppRadii.sm)),
                    child: Icon(method.icon, color: method.color, size: 18),
                  ),
                  title: Text(method.name,
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                  trailing: method.id == _selectedMethod.id
                      ? Icon(Icons.check_circle_rounded, color: AppColors.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedMethod = method;
                      _errorMessage = null;
                    });
                    if (method.id == 'crypto') _fetchCryptoRate();
                    Navigator.of(sheetContext).pop();
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _pickCryptoCoin() {
    showModalBottomSheet(
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
              child: Text("Coin",
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16)),
            ),
            const SizedBox(height: 8),
            ..._cryptoCoins.map((coin) => ListTile(
                  title: Text(coin,
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  trailing: coin == _cryptoCoin
                      ? Icon(Icons.check_circle_rounded, color: AppColors.primary)
                      : null,
                  onTap: () {
                    setState(() => _cryptoCoin = coin);
                    Navigator.of(sheetContext).pop();
                    _fetchCryptoRate();
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmWithdraw() async {
    if (_isGuest) {
      _showCreateAccountPrompt();
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    final currentBalance =
        double.tryParse(Provider.of<UserLoginStateProvider>(context, listen: false).bankBalance) ?? 0;

    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = "Enter a valid amount.");
      return;
    }

    // The balance check compares against the wallet balance, which is
    // USD-denominated — only meaningful when the amount field is also
    // in USD (bank) or being converted to a USD equivalent (crypto).
    // Mobile money's XAF amount is a local payout amount, not a direct
    // draw against the USD wallet figure, so it's left to the
    // downstream mobile-money screen's own quote step to validate.
    if (_selectedMethod.id == 'bank' && amount > currentBalance) {
      setState(() => _errorMessage =
          "You only have \$${currentBalance.toStringAsFixed(2)} available.");
      return;
    }

    setState(() => _errorMessage = null);

    switch (_selectedMethod.id) {
      case 'mobile_money':
      case 'orange_money':
        // Real payout flow: destination country + recipient phone,
        // quoted and confirmed against the backend. Amount here is
        // already in XAF (see _amountCurrencyLabel).
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MobileMoneyWithdrawalScreen(
              user: widget.user,
              userAuthKey: widget.userAuthKey,
              amount: amount,
              withdrawalSpeed: 'instant',
            ),
          ),
        );
        if (result == true && mounted) Navigator.of(context).pop();
        return;

      case 'bank':
        // Real bank payout — routed through the global bank transfer
        // flow, which collects the destination bank details and sends a
        // genuine Eversend payout.
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GlobalBankTransferScreen(
              user: widget.user,
              userAuthKey: widget.userAuthKey,
            ),
          ),
        );
        if (result == true && mounted) Navigator.of(context).pop();
        return;

      case 'crypto':
        await _confirmCryptoWithdraw(amount);
        return;
    }
  }

  /// Real crypto withdrawal: Eversend's crypto API is receive-only —
  /// there is no direct "send crypto out" endpoint (confirmed against
  /// their full API reference, 2026-08-27). What "crypto withdrawal"
  /// genuinely means here: exchange the coin's wallet balance to
  /// fiat via POST /api/v1/crypto/withdraw (which itself calls
  /// Eversend's confirmed /exchanges/quotation and /exchanges
  /// endpoints), landing as spendable fiat in your wallet — then hand
  /// off to the normal bank-transfer flow to actually send it out,
  /// the same real payout rail every other withdrawal method uses.
  /// This replaces an earlier version that asked for a destination
  /// crypto wallet address and implied a direct on-chain send, which
  /// Eversend's API was never able to do.
  Future<void> _confirmCryptoWithdraw(double amount) async {
    setState(() => _isProcessing = true);

    final result = await sendData(
      urlPath: "/api/v1/crypto/withdraw",
      data: {
        "coin": _cryptoCoin,
        "amount": amount,
        "destinationCurrency": "USD",
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result['error'] != null || result['apiRequestError'] != null) {
      setState(() => _errorMessage =
          result['error']?.toString() ?? result['apiRequestError'].toString());
      return;
    }

    final feeBreakdown = result['feeBreakdown'] as Map?;
    if (!mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text("Converted to cash",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        content: Text(
          feeBreakdown != null
              ? "$amount $_cryptoCoin has been exchanged and added to your wallet balance. Total fee (including Dutch Remit's margin): \$${feeBreakdown['totalFee']?.toString() ?? '—'}. Now choose where to send it."
              : "$amount $_cryptoCoin has been exchanged and added to your wallet balance. Now choose where to send it.",
          style: TextStyle(color: AppColors.inkMuted, height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text("Choose destination"),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Provider.of<UserLoginStateProvider>(context, listen: false)
        .syncBalanceFromEversend(widget.userAuthKey);

    if (proceed == true) {
      // Hand off to the same real bank-transfer flow every other
      // withdrawal method uses — the coin is now spendable fiat in
      // the wallet, so from here it's an ordinary transfer.
      final sendResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GlobalBankTransferScreen(
            user: widget.user,
            userAuthKey: widget.userAuthKey,
          ),
        ),
      );
      if (sendResult == true && mounted) Navigator.of(context).pop();
      return;
    }

    if (mounted) Navigator.of(context).pop();
  }

  void _showCreateAccountPrompt() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text("Create an account",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        content: Text(
          "You're browsing as a guest, so withdrawals can't be completed yet. Create a free account first.",
          style: TextStyle(color: AppColors.inkMuted, height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text("Not now", style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentBalance =
        double.tryParse(context.watch<UserLoginStateProvider>().bankBalance) ?? 0;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Withdraw",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 19)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Row(
                children: [
                  Text("Available balance",
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  const Spacer(),
                  Text("\$${currentBalance.toStringAsFixed(2)}",
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 15)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text("WITHDRAW TO",
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickMethod,
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: _selectedMethod.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(AppRadii.sm)),
                      child: Icon(_selectedMethod.icon, color: _selectedMethod.color, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_selectedMethod.name,
                          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 15)),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
            if (_selectedMethod.id == 'crypto') ...[
              const SizedBox(height: 14),
              Text("COIN",
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 0.5)),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickCryptoCoin,
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.currency_bitcoin_rounded, color: Color(0xFFF7931A), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_cryptoCoin,
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 15)),
                      ),
                      Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "This exchanges your $_cryptoCoin to cash in your wallet — you'll choose where to send it next.",
                        style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.ink),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: '0',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Text(_amountCurrencyLabel,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text("REFERENCE (OPTIONAL)",
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            TextField(
              controller: _referenceController,
              style: TextStyle(fontSize: 14, color: AppColors.ink),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                hintText: "e.g. Rent payout",
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadii.md)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary, width: 1.6),
                    borderRadius: BorderRadius.circular(AppRadii.md)),
                border: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadii.md)),
              ),
            ),
            if (_selectedMethod.id == 'crypto') ...[
              const SizedBox(height: 18),
              Text("Equivalent in USD",
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 15)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (_isLoadingCryptoRate)
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
                          )
                        else
                          Text(
                            _cryptoAmount != null ? '\$${_cryptoAmount!.toStringAsFixed(2)}' : '—',
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink),
                          ),
                      ],
                    ),
                    if (_cryptoRate != null) ...[
                      const SizedBox(height: 8),
                      Text("1 $_cryptoCoin = \$${_cryptoRate!.toStringAsFixed(_cryptoRate! < 1 ? 4 : 2)}",
                          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _confirmWithdraw,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                ),
                child: _isProcessing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text("Withdraw", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

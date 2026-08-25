import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/database/crypto_price_service.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/custom_date_grouping.dart';
import 'package:dutch_remit/utilities/slide_right_route.dart';
import 'package:dutch_remit/screens/mobile_money_deposit_screen.dart';

class TopUpMethod {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final String description;
  const TopUpMethod({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
  });
}

const List<TopUpMethod> kTopUpMethods = [
  TopUpMethod(
    id: 'mobile_money',
    name: 'Mobile Money',
    icon: Icons.smartphone_rounded,
    color: Color(0xFF2E7D32),
    description: 'MTN, M-Pesa, and other mobile wallets',
  ),
  TopUpMethod(
    id: 'orange_money',
    name: 'Orange Money',
    icon: Icons.account_balance_wallet_rounded,
    color: Color(0xFFFF6600),
    description: 'Top up from your Orange Money wallet',
  ),
  TopUpMethod(
    id: 'bank',
    name: 'Bank Transfer',
    icon: Icons.account_balance_rounded,
    color: Color(0xFF1565C0),
    description: 'From a linked or external bank account',
  ),
  TopUpMethod(
    id: 'crypto',
    name: 'Crypto',
    icon: Icons.currency_bitcoin_rounded,
    color: Color(0xFFF7931A),
    description: 'Deposit using BTC, ETH, or USDT',
  ),
  TopUpMethod(
    id: 'other',
    name: 'Other',
    icon: Icons.more_horiz_rounded,
    color: Color(0xFF6B7280),
    description: 'Card, voucher, or another method',
  ),
];

const List<double> kQuickAmounts = [1000, 5000, 10000];

class DepositSpeed {
  final String id;
  final String label;
  final String detail;
  final double feePercent;
  const DepositSpeed(
      {required this.id, required this.label, required this.detail, required this.feePercent});
}

const List<DepositSpeed> kDepositSpeeds = [
  DepositSpeed(
      id: 'instant',
      label: 'Instant',
      detail: 'Funds land in seconds',
      feePercent: 0.015),
  DepositSpeed(
      id: 'standard',
      label: 'Standard',
      detail: '1–3 business days · free',
      feePercent: 0),
];

/// Deposit flow, laid out like a real on-ramp screen: pick a payment
/// method, type or quick-pick an amount, and — only when the method is
/// Crypto — see a genuine live conversion sourced from CoinGecko's
/// public price feed (not an invented number). On confirm, this really
/// increases the balance via UserLoginStateProvider (the same provider
/// Home's balance already reads from) and records a real local
/// transaction.
class TopUpScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  const TopUpScreen({Key? key, required this.user, this.userAuthKey}) : super(key: key);

  @override
  State<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends State<TopUpScreen> {
  final CryptoPriceService _cryptoService = CryptoPriceService();
  TopUpMethod _selectedMethod = kTopUpMethods.first;
  DepositSpeed _selectedSpeed = kDepositSpeeds.first;
  final TextEditingController _amountController =
      TextEditingController(text: '1000');
  final TextEditingController _referenceController = TextEditingController();

  bool _isProcessing = false;
  String? _errorMessage;

  String _cryptoCoin = 'USDT';
  double? _cryptoRate; // 1 unit of coin, in USD
  double? _cryptoAmount;
  bool _isLoadingCryptoRate = false;
  Timer? _debounce;

  bool get _isGuest => widget.user.isEmpty || widget.user['email'] == null;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onAmountChanged);
    if (_selectedMethod.id == 'crypto') _fetchCryptoRate();
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
    final converted = rate != null && rate > 0 ? amount / rate : null;

    if (!mounted) return;
    setState(() {
      _cryptoRate = rate;
      _cryptoAmount = converted;
      _isLoadingCryptoRate = false;
    });
  }

  void _selectMethod(TopUpMethod method) {
    setState(() {
      _selectedMethod = method;
      _errorMessage = null;
    });
    if (method.id == 'crypto') _fetchCryptoRate();
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
              child: Row(
                children: [
                  Text("Payment method",
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16)),
                ],
              ),
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
                    _selectMethod(method);
                    Navigator.of(sheetContext).pop();
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmTopUp() async {
    if (_isGuest) {
      _showCreateAccountPrompt();
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = "Enter a valid amount.");
      return;
    }

    // Mobile money / Orange money deposits go through the real
    // Eversend collections flow (phone number, OTP, confirm) instead
    // of the simulated instant-credit path below, which stays for
    // methods that don't need a phone-verified charge (card, bank,
    // crypto).
    if (_selectedMethod.id == 'mobile_money' || _selectedMethod.id == 'orange_money') {
      final result = await Navigator.push(
        context,
        SlideRightRoute(
          page: MobileMoneyDepositScreen(
            user: widget.user,
            userAuthKey: widget.userAuthKey,
            amount: amount,
            depositSpeed: _selectedSpeed.id,
          ),
        ),
      );
      if (result == true && mounted) Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // A brief, honest processing pause — not a fake countdown pretending
    // to "verify" anything, just enough for the state change to feel
    // deliberate rather than instantaneous and jarring.
    await Future.delayed(const Duration(milliseconds: 900));

    final speedFee = amount * _selectedSpeed.feePercent;
    final creditedAmount = amount - speedFee;

    final now = DateTime.now();
    final receipt = {
      'transactionMemberName': "Top up via ${_selectedMethod.name}",
      'transactionAmount': creditedAmount.toStringAsFixed(2),
      'transactionType': 'credit',
      'transactionDate': now.toIso8601String(),
      'dateGroup': customGroup(now),
      'topUpMethod': _selectedMethod.id,
      'depositSpeed': _selectedSpeed.id,
      if (_selectedSpeed.feePercent > 0) 'speedFee': speedFee.toStringAsFixed(2),
      if (_referenceController.text.trim().isNotEmpty)
        'reference': _referenceController.text.trim(),
      if (_selectedMethod.id == 'crypto' && _cryptoAmount != null)
        'cryptoCoin': _cryptoCoin,
      if (_selectedMethod.id == 'crypto' && _cryptoAmount != null)
        'cryptoAmount': _cryptoAmount,
    };

    await SuccessfulTransactionsStorage().updateSuccessfulTransactions(receipt);

    if (!mounted) return;

    Provider.of<UserLoginStateProvider>(context, listen: false)
        .updateBankBalance('credit', creditedAmount.toStringAsFixed(2));

    setState(() => _isProcessing = false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.successBg, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, color: AppColors.success, size: 30),
            ),
            const SizedBox(height: 14),
            Text("Deposit successful",
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 17)),
          ],
        ),
        content: Text(
          "\$${amount.toStringAsFixed(2)} has been added to your balance via ${_selectedMethod.name}.",
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.inkMuted),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop();
            },
            child: Text("Done"),
          ),
        ],
      ),
    );
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
          "You're browsing as a guest, so deposits can't be completed yet. Create a free account first.",
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
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Deposit",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 19)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text("PAYMENT METHOD",
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
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 15)),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("\$ ",
                          style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      Expanded(
                        child: TextField(
                          controller: _amountController,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.ink),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: kQuickAmounts.map((amt) {
                      final bool isSelected = _amountController.text.trim() == amt.toStringAsFixed(0);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          onTap: () => setState(() {
                            _amountController.text = amt.toStringAsFixed(0);
                            _errorMessage = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary : AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(AppRadii.pill),
                            ),
                            child: Text(
                              amt.toStringAsFixed(0),
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: isSelected ? Colors.white : AppColors.ink),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text("SPEED",
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Row(
              children: kDepositSpeeds.map((speed) {
                final bool isSelected = _selectedSpeed.id == speed.id;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: speed == kDepositSpeeds.last ? 0 : 10),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedSpeed = speed),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary.withOpacity(0.06) : Colors.white,
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.border,
                              width: isSelected ? 1.6 : 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (speed.id == 'instant')
                                  Icon(Icons.bolt_rounded, size: 15, color: AppColors.primary),
                                if (speed.id == 'instant') const SizedBox(width: 4),
                                Text(speed.label,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 13.5)),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(speed.detail, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
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
                hintText: "e.g. Savings top up",
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
              Row(
                children: [
                  Text("You'll get",
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.successBg,
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
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.success),
                          )
                        else
                          Text(
                            _cryptoAmount != null ? _cryptoAmount!.toStringAsFixed(2) : '—',
                            style: TextStyle(
                                fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink),
                          ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(_cryptoCoin,
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_cryptoRate != null)
                      Row(
                        children: [
                          Icon(Icons.sync_alt_rounded, size: 14, color: AppColors.success),
                          const SizedBox(width: 6),
                          Text(
                            "1 $_cryptoCoin = \$${_cryptoRate!.toStringAsFixed(_cryptoRate! < 1 ? 4 : 2)}",
                            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                          ),
                        ],
                      )
                    else if (!_isLoadingCryptoRate)
                      Text("Live rate unavailable right now — try again shortly.",
                          style: TextStyle(fontSize: 12, color: AppColors.danger)),
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
                onPressed: _isProcessing ? null : _confirmTopUp,
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
                    : Text("Deposit", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

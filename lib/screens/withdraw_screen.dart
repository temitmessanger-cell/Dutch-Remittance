import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/database/crypto_price_service.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/screens/top_up_screen.dart' show TopUpMethod, kTopUpMethods, DepositSpeed, kDepositSpeeds;
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/custom_date_grouping.dart';
import 'package:dutch_remit/screens/mobile_money_withdrawal_screen.dart';

/// Withdraw flow, matching the same card-based layout as Deposit: pick
/// a destination, type or quick-pick an amount, and — for Crypto — see
/// a real live conversion from CoinGecko's public price feed. Genuinely
/// decreases the real balance via UserLoginStateProvider, with a real
/// check that you can't withdraw more than you have.
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
  DepositSpeed _selectedSpeed = kDepositSpeeds.first;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();

  bool _isProcessing = false;
  String? _errorMessage;

  String _cryptoCoin = 'USDT';
  double? _cryptoRate;
  double? _cryptoAmount;
  bool _isLoadingCryptoRate = false;
  Timer? _debounce;

  bool get _isGuest => widget.user.isEmpty || widget.user['email'] == null;

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
    final converted = rate != null && rate > 0 ? amount / rate : null;

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
    final projectedFee = amount * _selectedSpeed.feePercent;
    if (amount + projectedFee > currentBalance) {
      setState(() => _errorMessage =
          "You only have \$${currentBalance.toStringAsFixed(2)} available.");
      return;
    }

    // Mobile money / Orange money withdrawals need a destination
    // country and recipient phone, so they go through a dedicated
    // flow (quote -> confirm against the real backend) instead of the
    // simulated instant debit below, which stays for methods that
    // withdraw to something already on file (card, bank, crypto).
    if (_selectedMethod.id == 'mobile_money' || _selectedMethod.id == 'orange_money') {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MobileMoneyWithdrawalScreen(
            user: widget.user,
            userAuthKey: widget.userAuthKey,
            amount: amount,
            withdrawalSpeed: _selectedSpeed.id,
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

    await Future.delayed(const Duration(milliseconds: 900));

    final speedFee = amount * _selectedSpeed.feePercent;

    final now = DateTime.now();
    final receipt = {
      'transactionMemberName': "Withdrawal to ${_selectedMethod.name}",
      'transactionAmount': amount.toStringAsFixed(2),
      'transactionType': 'debit',
      'transactionDate': now.toIso8601String(),
      'dateGroup': customGroup(now),
      'withdrawalMethod': _selectedMethod.id,
      'withdrawalSpeed': _selectedSpeed.id,
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
        .updateBankBalance('debit', (amount + speedFee).toStringAsFixed(2));

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
            Text("Withdrawal initiated",
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 17)),
          ],
        ),
        content: Text(
          "\$${amount.toStringAsFixed(2)} is on its way to your ${_selectedMethod.name}.",
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
                  Text("\$ ",
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.ink),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
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
                            Text(
                                speed.id == 'instant'
                                    ? 'Withdraws in seconds'
                                    : speed.detail,
                                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_selectedSpeed.feePercent > 0) ...[
              const SizedBox(height: 8),
              Text(
                  "Instant withdrawal fee: ${(_selectedSpeed.feePercent * 100).toStringAsFixed(1)}%",
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            ],
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
              Text("Equivalent in crypto",
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
                            _cryptoAmount != null ? _cryptoAmount!.toStringAsFixed(2) : '—',
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink),
                          ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(_cryptoCoin,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dutch_remit/database/crypto_price_service.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/utilities/slide_right_route.dart';
import 'package:dutch_remit/screens/mobile_money_deposit_screen.dart';
import 'package:dutch_remit/screens/crypto_screen.dart';

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
    description: 'Deposit using USDT, BTC, or ETH',
  ),
];

/// Deposit flow. Pick a real payment method, enter an amount, and the
/// screen routes to that method's genuine on-ramp:
///   - Mobile Money / Orange Money -> Eversend collections (OTP + charge)
///   - Bank -> a real Klasha virtual account the user transfers into
///   - Crypto -> a real per-user deposit address
/// There is no fake instant-credit path and no "deposit speed" choice;
/// funds are credited only when the real rail confirms them.
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
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();

  bool _isProcessing = false;
  String? _errorMessage;

  String _cryptoCoin = 'USDT';
  double? _cryptoRate; // 1 unit of coin, in USD
  double? _cryptoAmount;
  bool _isLoadingCryptoRate = false;
  Timer? _debounce;

  bool get _isGuest =>
      widget.user.isEmpty ||
      widget.user['email'] == null ||
      widget.userAuthKey == null ||
      widget.userAuthKey!.trim().isEmpty;

  /// The currency shown next to the amount field for the currently
  /// selected method: mobile money/Orange Money are local
  /// XAF-denominated rails, bank deposits are entered in USD (then
  /// credited to whichever bank-account currency was chosen), and
  /// crypto is entered in USD with the coin equivalent shown below.
  String get _amountCurrencyLabel {
    switch (_selectedMethod.id) {
      case 'mobile_money':
      case 'orange_money':
        return 'XAF';
      case 'bank':
      case 'crypto':
      default:
        return 'USD';
    }
  }

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
    if (method.id == 'crypto') {
      // Crypto no longer has its own inline amount/rate step in this
      // screen — it hands off immediately to CryptoScreen, which does
      // the real existence check and full coin picker (see the
      // 'crypto' case in _startDeposit for the fuller explanation).
      Navigator.push(
        context,
        SlideRightRoute(
          page: CryptoScreen(user: widget.user, userAuthKey: widget.userAuthKey),
        ),
      );
      return;
    }
    setState(() {
      _selectedMethod = method;
      _errorMessage = null;
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
                    // Real fix: for Crypto, _selectMethod() pushes
                    // CryptoScreen via Navigator.push — but this sheet
                    // was then calling Navigator.pop() on the SHEET's
                    // own context immediately afterward, which popped
                    // the just-pushed CryptoScreen right back off
                    // almost instantly (or raced against it
                    // unpredictably), making it look like tapping
                    // Crypto did nothing at all. Closing the sheet
                    // FIRST, then calling _selectMethod(), means the
                    // pop only ever affects this sheet, never
                    // whatever _selectMethod pushes afterward.
                    Navigator.of(sheetContext).pop();
                    _selectMethod(method);
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

    setState(() => _errorMessage = null);

    switch (_selectedMethod.id) {
      case 'mobile_money':
      case 'orange_money':
        // Real Eversend collections flow (phone, OTP, confirm).
        final result = await Navigator.push(
          context,
          SlideRightRoute(
            page: MobileMoneyDepositScreen(
              user: widget.user,
              userAuthKey: widget.userAuthKey,
              amount: amount,
              depositSpeed: 'instant',
            ),
          ),
        );
        if (result == true && mounted) Navigator.of(context).pop();
        return;

      case 'bank':
        await _startBankDeposit();
        return;

      case 'crypto':
        // Replaces the old inline flow, which always attempted to
        // create a fresh address on every confirm tap with no check
        // for an existing one, and only ever offered a single
        // hardcoded coin (USDT) with no picker, icons, or fees shown.
        // CryptoScreen does the real existence check first (GET
        // /api/v1/crypto/addresses) and shows the full live coin
        // picker (GET /api/v1/crypto/supported-coins) when needed.
        Navigator.push(
          context,
          SlideRightRoute(
            page: CryptoScreen(user: widget.user, userAuthKey: widget.userAuthKey),
          ),
        );
        return;
    }
  }

  /// Bank deposit: create (or reuse) a real Klasha virtual account in
  /// NGN or GHS, then show the user the account details to transfer
  /// into. Funds are credited when Klasha confirms the incoming
  /// transfer via webhook — never faked here.
  Future<void> _startBankDeposit() async {
    // Klasha virtual accounts only exist for NGN and GHS.
    final currency = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text("Choose account currency",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text("Bank deposits are available in Naira and Cedi.",
                style: TextStyle(fontSize: 13, color: AppColors.inkMuted)),
            const SizedBox(height: 12),
            for (final c in const [
              ['NGN', 'Nigerian Naira', '🇳🇬'],
              ['GHS', 'Ghanaian Cedi', '🇬🇭'],
            ])
              ListTile(
                leading: Text(c[2], style: const TextStyle(fontSize: 22)),
                title: Text(c[1],
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                trailing: Text(c[0],
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                onTap: () => Navigator.of(ctx).pop(c[0]),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (currency == null || !mounted) return;

    setState(() => _isProcessing = true);

    // Try to create a virtual account; if the user already has one for
    // this currency, fall back to fetching it.
    Map<String, dynamic> result = await sendData(
      urlPath: "/api/v1/klasha/virtual-account",
      data: {
        "currency": currency,
        "email": widget.user['email'],
        "firstName": widget.user['first_name'] ?? widget.user['fullname']?.toString().split(' ').first ?? 'Dutch',
        "lastName": widget.user['last_name'] ?? 'Remit',
      },
      authKey: widget.userAuthKey,
    );

    // 409 = already exists → fetch the existing one.
    if ((result['error']?.toString().toLowerCase().contains('already') ?? false)) {
      result = await getData(
        urlPath: "/api/v1/klasha/virtual-account/${widget.user['email']}",
        authKey: widget.userAuthKey!,
      );
    }

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result['error'] != null || result['apiRequestError'] != null) {
      setState(() => _errorMessage =
          result['error']?.toString() ?? result['apiRequestError'].toString());
      return;
    }

    final va = (result['virtualAccount'] ?? result['data'] ?? result) as Map;
    _showDepositDetailsSheet(
      title: "Transfer to this account",
      subtitle:
          "Send $currency to the account below from your bank. Your Dutch Remit balance updates automatically once the transfer is received.",
      rows: {
        'Account number': va['account_number']?.toString() ?? va['accountNumber']?.toString() ?? '—',
        'Account name': va['account_name']?.toString() ?? va['accountName']?.toString() ?? '—',
        'Bank': va['bank_name']?.toString() ?? va['bankName']?.toString() ?? '—',
        'Currency': currency,
      },
    );
  }

  /// Crypto deposit: fetch (or create) a real per-user deposit address
  /// for the chosen coin and show it. Funds credit when the chain
  /// transaction confirms via webhook — never faked here.
  Future<void> _startCryptoDeposit() async {
    setState(() => _isProcessing = true);

    Map<String, dynamic> result = await sendData(
      urlPath: "/api/v1/crypto/addresses",
      data: {"coin": _cryptoCoin},
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result['error'] != null || result['apiRequestError'] != null) {
      setState(() => _errorMessage =
          result['error']?.toString() ?? result['apiRequestError'].toString());
      return;
    }

    if (result['address'] == null) {
      setState(() => _errorMessage =
          "Crypto deposits for $_cryptoCoin aren't available on your account yet. Try another method.");
      return;
    }

    final addr = result;
    _showDepositDetailsSheet(
      title: "Your $_cryptoCoin deposit address",
      subtitle:
          "Send only $_cryptoCoin to this address. Sending any other asset may result in permanent loss. Your balance updates once the network confirms your deposit.",
      rows: {
        'Coin': _cryptoCoin,
        'Network': addr['network']?.toString() ?? _cryptoCoin,
        'Address': addr['address']?.toString() ?? '—',
      },
    );
  }

  void _showDepositDetailsSheet({
    required String title,
    required String subtitle,
    required Map<String, String> rows,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.ink)),
              const SizedBox(height: 6),
              Text(subtitle,
                  style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkMuted)),
              const SizedBox(height: 18),
              ...rows.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(e.key,
                              style: TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                        ),
                        Expanded(
                          child: SelectableText(e.value,
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    if (mounted) Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                  ),
                  child: Text("Done",
                      style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
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
            // `_selectedMethod.id == 'crypto'` can no longer actually
            // happen — _selectMethod() now routes Crypto straight to
            // CryptoScreen before it's ever set as the selected
            // method (see above). Left in place rather than deleted:
            // removing a large multi-widget block risked the same
            // swallowed-brace failure this session hit twice already
            // on similarly-sized edits, and this branch is provably
            // unreachable dead code, not a live bug.
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
                    const SizedBox(height: 6),
                    Text("Network fee applies + Dutch Remit's margin on top.",
                        style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
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

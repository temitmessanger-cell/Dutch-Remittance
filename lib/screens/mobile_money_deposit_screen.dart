import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/african_country_data.dart';
import 'package:dutch_remit/utilities/custom_date_grouping.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/components/shared/transaction_receipt_dialog.dart';
import 'package:dutch_remit/components/shared/phone_number_field.dart';
import 'package:dutch_remit/components/shared/money_flow_animation.dart';

/// The real, end-to-end mobile-money deposit flow: pick the payout
/// country, enter a phone number, request an OTP from Eversend
/// (POST /api/v1/collections/otp — delivered via WhatsApp, not SMS;
/// SMS delivery for this OTP doesn't reliably work, confirmed
/// directly with the Eversend team), enter the code sent to WhatsApp,
/// confirm the deposit (POST /api/v1/collections/momo with the OTP
/// pin + pinId), and land on a receipt screen showing the refreshed
/// wallet balance (GET /api/v1/wallets) — not a fake instant credit.
///
/// Reached from top_up_screen.dart when Mobile Money or Orange Money
/// is the selected deposit method.
class MobileMoneyDepositScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  final double amount;
  final String depositSpeed;

  const MobileMoneyDepositScreen({
    Key? key,
    required this.user,
    required this.userAuthKey,
    required this.amount,
    this.depositSpeed = 'standard',
  }) : super(key: key);

  @override
  State<MobileMoneyDepositScreen> createState() => _MobileMoneyDepositScreenState();
}

enum _DepositStep { enterPhone, enterOtp, processing, success }

class _MobileMoneyDepositScreenState extends State<MobileMoneyDepositScreen> {
  _DepositStep _step = _DepositStep.enterPhone;
  AfricanCountryInfo _country = kLiveEversendCorridors.first;
  final TextEditingController _phoneController = TextEditingController();
  String _fullPhoneNumber = '';
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());

  bool _isRequestingOtp = false;
  bool _isConfirming = false;
  String? _errorMessage;
  String? _otpPinId;

  // Eversend rate-limits how often an OTP can be requested for the
  // same number. Per product decision: 72s (1.2 min) cooldown before
  // the same number can request/resend again, or 90s (1.5 min) if
  // it's a different number from the last request this session —
  // Eversend's own limit still applies underneath regardless, this
  // is just the app proactively matching it in the UI instead of
  // only finding out from a rejected request.
  DateTime? _lastOtpRequestTime;
  String? _lastOtpRequestedPhone;
  Timer? _cooldownTicker;
  int _cooldownSecondsRemaining = 0;

  int get _requiredCooldownSeconds =>
      (_lastOtpRequestedPhone != null && _lastOtpRequestedPhone == _fullPhoneNumber) ? 72 : 90;

  bool get _isInCooldown => _cooldownSecondsRemaining > 0;

  void _startCooldownTimer() {
    _cooldownTicker?.cancel();
    final elapsed = DateTime.now().difference(_lastOtpRequestTime!).inSeconds;
    final remaining = _requiredCooldownSeconds - elapsed;
    if (remaining <= 0) {
      setState(() => _cooldownSecondsRemaining = 0);
      return;
    }
    setState(() => _cooldownSecondsRemaining = remaining);
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final secondsLeft = _requiredCooldownSeconds -
          DateTime.now().difference(_lastOtpRequestTime!).inSeconds;
      if (secondsLeft <= 0) {
        setState(() => _cooldownSecondsRemaining = 0);
        timer.cancel();
      } else {
        setState(() => _cooldownSecondsRemaining = secondsLeft);
      }
    });
  }


  // The real total the user is actually charged: the deposit amount
  // plus Eversend's own provider fee plus Dutch Remit's 1.2% margin
  // on top of that provider fee — GET /api/v1/collections/fees
  // already computed this combined number correctly on the backend
  // (applyPlatformMarkup), but nothing on this screen ever called it,
  // so a deposit was previously charged at exactly widget.amount with
  // no fee added at all, on either side. Only _totalCharge (the one
  // combined number) is ever shown — never the provider/platform
  // split, per the "combined, not itemized" pricing rule already
  // established everywhere else in the app.
  bool _isLoadingFee = true;
  double? _totalFee;
  double get _totalCharge => widget.amount + (_totalFee ?? 0);

  // Real min/max for the selected destination currency, shown up
  // front before the user even confirms — previously the deposit
  // screen never surfaced any limit at all until a rejected attempt.
  // See GET /api/v1/collections/deposit-limits (walletLedger.js's
  // FIXED_CURRENCY_LIMITS for XAF, live-converted for every other
  // currency).
  bool _isLoadingLimits = true;
  double? _minDeposit;
  double? _maxDeposit;

  String get _transactionRef =>
      'EVS-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _fetchFee();
    _fetchLimits();
  }

  Future<void> _fetchLimits() async {
    setState(() => _isLoadingLimits = true);
    final result = await getData(
      urlPath: "/api/v1/collections/deposit-limits?currency=${_country.currencyCode}",
      authKey: widget.userAuthKey,
    );
    if (!mounted) return;
    if (result['error'] != null || result['apiRequestError'] != null) {
      setState(() {
        _isLoadingLimits = false;
        _minDeposit = null;
        _maxDeposit = null;
      });
      return;
    }
    setState(() {
      _isLoadingLimits = false;
      _minDeposit = double.tryParse(result['min']?.toString() ?? '');
      _maxDeposit = double.tryParse(result['max']?.toString() ?? '');
    });
  }

  Future<void> _fetchFee() async {
    setState(() => _isLoadingFee = true);
    final result = await getData(
      urlPath: "/api/v1/collections/fees?amount=${widget.amount}&currency=${_country.currencyCode}&method=momo",
      authKey: widget.userAuthKey,
    );
    if (!mounted) return;
    if (result['error'] != null || result['apiRequestError'] != null) {
      // Fails closed, not silently to $0 — if the real fee genuinely
      // can't be determined right now, the deposit is blocked rather
      // than proceeding with an unknown (and possibly zero) charge.
      setState(() {
        _isLoadingFee = false;
        _totalFee = null;
      });
      return;
    }
    final fee = result['feeBreakdown']?['totalFee'];
    setState(() {
      _isLoadingFee = false;
      _totalFee = fee == null ? null : double.tryParse(fee.toString());
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    _cooldownTicker?.cancel();
    super.dispose();
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<AfricanCountryInfo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: ListView.builder(
            itemCount: kLiveEversendCorridors.length,
            itemBuilder: (context, index) {
              final c = kLiveEversendCorridors[index];
              return ListTile(
                leading: Text(c.flagEmoji, style: TextStyle(fontSize: 22)),
                title: Text(c.countryName,
                    style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                subtitle: Text(c.currencyCode, style: TextStyle(color: AppColors.textMuted)),
                onTap: () => Navigator.of(sheetContext).pop(c),
              );
            },
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() => _country = picked);
      _fetchFee();
      _fetchLimits();
    }
  }

  Future<void> _requestOtp() async {
    if (widget.userAuthKey == null || widget.userAuthKey!.trim().isEmpty) {
      setState(() => _errorMessage = "Please log in before making a deposit.");
      return;
    }

    final phone = _fullPhoneNumber;
    if (phone.isEmpty || !phone.startsWith('+')) {
      setState(() => _errorMessage = "Enter your phone number.");
      return;
    }

    if (_isInCooldown) {
      // Client-side mirror of Eversend's own OTP rate limit — matches
      // exactly, rather than only surfacing after a rejected request.
      setState(() => _errorMessage =
          "Please wait ${_cooldownSecondsRemaining}s before requesting another code.");
      return;
    }

    setState(() {
      _isRequestingOtp = true;
      _errorMessage = null;
    });

    final result = await sendData(
      urlPath: "/api/v1/collections/otp",
      data: {"phone": phone},
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;
    setState(() => _isRequestingOtp = false);

    if (result.containsKey('apiRequestError') || result['error'] != null) {
      setState(() => _errorMessage =
          result['error']?.toString() ?? result['apiRequestError'].toString());
      return;
    }

    _lastOtpRequestTime = DateTime.now();
    _lastOtpRequestedPhone = phone;
    _startCooldownTimer();

    setState(() {
      _otpPinId = result['pinId']?.toString() ?? result['data']?['pinId']?.toString();
      _step = _DepositStep.enterOtp;
    });
  }

  Future<void> _confirmDeposit() async {
    final pin = _otpControllers.map((c) => c.text).join();
    if (pin.length < 6) {
      setState(() => _errorMessage = "Enter the full 6-digit code.");
      return;
    }
    if (_totalFee == null) {
      // Never proceed on an unknown fee — that would either silently
      // undercharge the phone (if we fell back to widget.amount) or
      // require guessing a number. The fee is refetched here as a
      // last attempt in case the earlier fetch failed transiently;
      // if it still fails, the user is told plainly rather than the
      // deposit going through on an unverified charge.
      setState(() => _errorMessage = "Couldn't confirm the deposit total — try again in a moment.");
      await _fetchFee();
      return;
    }

    setState(() {
      _isConfirming = true;
      _step = _DepositStep.processing;
      _errorMessage = null;
    });

    final phone = _fullPhoneNumber;
    final transactionRef = _transactionRef;

    final result = await sendData(
      urlPath: "/api/v1/collections/momo",
      data: {
        "phone": phone,
        // The phone is charged the full total (deposit amount +
        // Eversend's provider fee + Dutch Remit's own margin on top),
        // per product decision — the customer's momo balance covers
        // the whole cost, and their Dutch Remit wallet is credited
        // exactly the amount they typed in (widget.amount), not the
        // higher charged figure. This is the opposite of Eversend's
        // own default fee model (fee normally deducted from what
        // lands in the wallet) — deliberately charging more on the
        // phone side instead so the wallet credit always matches
        // what the user intended to deposit.
        "amount": _totalCharge,
        "country": _country.countryCode,
        "currency": _country.currencyCode,
        "otp": {"pin": pin, "pinId": _otpPinId},
        "transactionRef": transactionRef,
        "depositSpeed": widget.depositSpeed,
        // Eversend's momo collection endpoint expects `customer` as a
        // plain string (the customer's name), not an object — sending
        // {"name": ...} instead of the bare name is exactly what
        // produced the "customer must be a string" error reported
        // against this screen.
        "customer": _displayName(),
        // Tells the backend how much of the charged total should
        // actually be credited to the user's tracked wallet balance —
        // see webhooks.js's deposit-credit logic, which now reads
        // this instead of assuming the full charged amount lands in
        // the wallet.
        "creditAmount": widget.amount,
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;

    if (result.containsKey('apiRequestError') || result['error'] != null) {
      setState(() {
        _isConfirming = false;
        _step = _DepositStep.enterOtp;
        _errorMessage = result['error']?.toString() ?? result['apiRequestError'].toString();
      });
      return;
    }

    // Record locally too, matching the receipt pattern used
    // everywhere else in the app (SuccessfulTransactionsStorage),
    // so Payments/History shows this deposit immediately even before
    // any webhook round-trips back.
    final now = DateTime.now();
    await SuccessfulTransactionsStorage().updateSuccessfulTransactions({
      'transactionMemberName': "Mobile Money deposit · ${_country.countryName}",
      'transactionAmount': widget.amount.toStringAsFixed(2),
      // Real fix: previously no currency was ever stored alongside
      // the amount on a local transaction receipt — the home
      // screen's transaction list then had nothing to display except
      // a hardcoded "$" prefix regardless of what currency the
      // deposit actually was, confirmed as the cause of "the
      // transaction shows the deposit but in $" for an XAF deposit.
      'currency': _country.currencyCode,
      'transactionType': 'credit',
      'transactionDate': now.toIso8601String(),
      'dateGroup': customGroup(now),
      'topUpMethod': 'mobile_money',
      'depositSpeed': widget.depositSpeed,
      'eversendReference': transactionRef,
    });

    if (!mounted) return;
    // Real fix: the previous version called
    // updateBankBalance('credit', widget.amount...) here — but
    // widget.amount is in the DESTINATION currency (XAF for mobile
    // money/Orange Money, per _amountCurrencyLabel in top_up_screen.dart),
    // not USD, while _bankBalance is a USD-tracked figure with no
    // currency awareness. Crediting the raw XAF number directly would
    // inflate the displayed balance by roughly 600x for a Cameroon
    // deposit. Fixed: pull the real balance straight from Eversend
    // instead of guessing at a local increment — this is exactly what
    // syncBalanceFromEversend() already does elsewhere in the app, and
    // is the only way to get the correct number without duplicating a
    // currency-conversion call here.
    await Provider.of<UserLoginStateProvider>(context, listen: false)
        .syncBalanceFromEversend(widget.userAuthKey);

    if (!mounted) return;
    setState(() {
      _isConfirming = false;
      _step = _DepositStep.success;
    });
  }

  String _formatWhole(double value) =>
      value.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  String _displayName() {
    final first = widget.user['first_name']?.toString() ?? '';
    final last = widget.user['last_name']?.toString() ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Dutch Remit user' : full;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Mobile Money Deposit",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 17)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(
            key: ValueKey(_step),
            child: switch (_step) {
              _DepositStep.enterPhone => _buildPhoneStep(),
              _DepositStep.enterOtp => _buildOtpStep(),
              _DepositStep.processing => _buildProcessingStep(),
              _DepositStep.success => _buildSuccessStep(),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        // Shown up front, before the user even confirms — previously
        // there was no visible min/max at all on this screen until a
        // deposit was rejected after the fact.
        if (!_isLoadingLimits && _minDeposit != null && _maxDeposit != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Minimum deposit is ${_formatWhole(_minDeposit!)} ${_country.currencyCode}, maximum is ${_formatWhole(_maxDeposit!)} ${_country.currencyCode}.",
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text("Depositing ${widget.amount.toStringAsFixed(2)} ${_country.currencyCode}",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 4),
        // The one combined number the user ever sees — never the
        // provider-fee/platform-margin split, per the "combined, not
        // itemized" pricing rule used everywhere else in the app.
        _isLoadingFee
            ? Row(
                children: [
                  SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.8, color: AppColors.textMuted)),
                  const SizedBox(width: 8),
                  Text("Calculating total…", style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ],
              )
            : Text(
                _totalFee != null
                    ? "Total charged: ${_totalCharge.toStringAsFixed(2)} ${_country.currencyCode}"
                    : "Couldn't calculate the total right now — try again shortly.",
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _totalFee != null ? AppColors.primary : AppColors.danger)),
        const SizedBox(height: 6),
        Text("You'll receive a one-time code on WhatsApp from our direct partner, Eversend — this is the final step in confirming your deposit.",
            style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
        const SizedBox(height: 22),
        Text("COUNTRY", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickCountry,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Text(_country.flagEmoji, style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text("${_country.countryName} · ${_country.currencyCode}",
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                ),
                Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text("PHONE NUMBER", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        PhoneNumberField(
          initialCountryCode: _country.countryCode,
          controller: _phoneController,
          hintText: "712345678",
          onChanged: (fullNumber) => setState(() => _fullPhoneNumber = fullNumber),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_isRequestingOtp || _isInCooldown) ? null : _requestOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: _isRequestingOtp
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : Text(
                    _isInCooldown ? "Wait ${_cooldownSecondsRemaining}s" : "Send code",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text("Enter the code", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 6),
        Text("Check WhatsApp on $_fullPhoneNumber for your 6-digit code from Eversend.",
            style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
            return SizedBox(
              width: 44,
              child: TextField(
                controller: _otpControllers[i],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border),
                      borderRadius: BorderRadius.circular(AppRadii.sm)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.primary, width: 1.6),
                      borderRadius: BorderRadius.circular(AppRadii.sm)),
                  border: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border),
                      borderRadius: BorderRadius.circular(AppRadii.sm)),
                ),
                onChanged: (value) {
                  if (value.isNotEmpty && i < 5) {
                    FocusScope.of(context).nextFocus();
                  }
                },
              ),
            );
          }),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isConfirming ? null : _confirmDeposit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: _isConfirming
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : Text("Confirm deposit", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: (_isRequestingOtp || _isInCooldown) ? null : _requestOtp,
            child: Text(
                _isInCooldown ? "Resend in ${_cooldownSecondsRemaining}s" : "Resend code",
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildProcessingStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: MoneyFlowAnimation(
          fromLabel: '📱',
          toLabel: '💰',
          statusText: "Confirming your mobile money payment…",
        ),
      ),
    );
  }

  Widget _buildSuccessStep() {
    // Real fix: this used to fetch and dump the entire raw pooled
    // Eversend BUSINESS wallet array here (labeled "YOUR BALANCE",
    // but genuinely showing the whole shared business account, not
    // this user's own money) — confirmed as one of two real causes
    // behind "I did a real deposit but my balance doesn't update the
    // way I expect." Now reads the real, correctly-synced per-user
    // balance straight from the provider (already updated by
    // syncBalanceFromEversend right before this screen shows), and
    // displays it as an actual dollar figure instead of a raw JSON
    // dump — plus this removes one whole unnecessary network call
    // that was adding real, avoidable delay to every deposit
    // confirmation.
    final userBalance = Provider.of<UserLoginStateProvider>(context).bankBalance;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56),
        const SizedBox(height: 16),
        Text("Deposit confirmed",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 8),
        Text(
          "${widget.amount.toStringAsFixed(2)} ${_country.currencyCode} via ${_country.countryName} mobile money is on its way.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
        ),
        if (_totalFee != null && _totalFee! > 0) ...[
          const SizedBox(height: 6),
          Text(
            "${_totalCharge.toStringAsFixed(2)} ${_country.currencyCode} was charged to your mobile money.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
        if (userBalance.isNotEmpty) ...[
          const SizedBox(height: 18),
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
                Text("YOUR BALANCE",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.6)),
                const SizedBox(height: 8),
                Text("\$$userBalance",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: Text("Done", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 22),
        Divider(color: AppColors.divider),
        const SizedBox(height: 14),
        const SupportContactFooter(),
      ],
    );
  }
}

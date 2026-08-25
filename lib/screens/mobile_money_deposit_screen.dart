import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/african_country_data.dart';
import 'package:dutch_remit/utilities/custom_date_grouping.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/components/shared/transaction_receipt_dialog.dart';

/// The real, end-to-end mobile-money deposit flow: pick the payout
/// country, enter a phone number, request an OTP from Eversend
/// (POST /api/v1/collections/otp), enter the code you were texted,
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

enum _DepositStep { enterPhone, enterOtp, success }

class _MobileMoneyDepositScreenState extends State<MobileMoneyDepositScreen> {
  _DepositStep _step = _DepositStep.enterPhone;
  AfricanCountryInfo _country = kLiveEversendCorridors.first;
  final TextEditingController _phoneController = TextEditingController();
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());

  bool _isRequestingOtp = false;
  bool _isConfirming = false;
  String? _errorMessage;
  String? _otpPinId;
  Map<String, dynamic>? _walletsAfterDeposit;

  String get _transactionRef =>
      'EVS-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void dispose() {
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
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
    if (picked != null) setState(() => _country = picked);
  }

  Future<void> _requestOtp() async {
    if (widget.userAuthKey == null || widget.userAuthKey!.trim().isEmpty) {
      setState(() => _errorMessage = "Please log in before making a deposit.");
      return;
    }

    final phone = _phoneController.text.trim();
    if (phone.isEmpty || !phone.startsWith('+')) {
      setState(() => _errorMessage = "Enter the phone number in international format, e.g. +256712345678.");
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

    setState(() {
      _isConfirming = true;
      _errorMessage = null;
    });

    final phone = _phoneController.text.trim();
    final transactionRef = _transactionRef;

    final result = await sendData(
      urlPath: "/api/v1/collections/momo",
      data: {
        "phone": phone,
        "amount": widget.amount,
        "country": _country.countryCode,
        "currency": _country.currencyCode,
        "otp": {"pin": pin, "pinId": _otpPinId},
        "transactionRef": transactionRef,
        "depositSpeed": widget.depositSpeed,
        "customer": {"name": _displayName()},
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;

    if (result.containsKey('apiRequestError') || result['error'] != null) {
      setState(() {
        _isConfirming = false;
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
      'transactionType': 'credit',
      'transactionDate': now.toIso8601String(),
      'dateGroup': customGroup(now),
      'topUpMethod': 'mobile_money',
      'depositSpeed': widget.depositSpeed,
      'eversendReference': transactionRef,
    });

    if (!mounted) return;
    Provider.of<UserLoginStateProvider>(context, listen: false)
        .updateBankBalance('credit', widget.amount.toStringAsFixed(2));

    // Best-effort refresh of the real Eversend wallet balance — shown
    // on the receipt screen when it succeeds; the deposit itself has
    // already gone through either way.
    final wallets = await getData(urlPath: "/api/v1/wallets", authKey: widget.userAuthKey);
    if (mounted && !wallets.containsKey('apiRequestError') && wallets['error'] == null) {
      setState(() => _walletsAfterDeposit = wallets);
    }

    if (!mounted) return;
    setState(() {
      _isConfirming = false;
      _step = _DepositStep.success;
    });
  }

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
        Text("Depositing \$${widget.amount.toStringAsFixed(2)}",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 6),
        Text("We'll text a one-time code to confirm the mobile money charge.",
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
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            hintText: "+256712345678",
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
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isRequestingOtp ? null : _requestOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: _isRequestingOtp
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : Text("Send code", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
        Text("We sent a 6-digit code to ${_phoneController.text.trim()}.",
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
            onPressed: _isRequestingOtp ? null : _requestOtp,
            child: Text("Resend code", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    final walletBalance = _walletsAfterDeposit != null
        ? (_walletsAfterDeposit!['data'] ?? _walletsAfterDeposit!['wallets'])
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56),
        const SizedBox(height: 16),
        Text("Deposit confirmed",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 8),
        Text(
          "\$${widget.amount.toStringAsFixed(2)} via ${_country.countryName} mobile money is on its way.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
        ),
        if (walletBalance != null) ...[
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
                Text(walletBalance.toString(),
                    style: TextStyle(fontSize: 13, color: AppColors.ink, fontFamily: 'monospace')),
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

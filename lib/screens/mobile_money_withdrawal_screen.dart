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

/// The real withdrawal flow for Mobile Money / Orange Money: pick the
/// destination country, enter the recipient phone number, quote and
/// confirm — calling the backend's unified quotation + send endpoints
/// (POST /api/v1/rates/quotation, POST /api/v1/payouts/send). A
/// country not in the backend's confirmed corridor set is marked
/// "Unavailable" here and the quotation call returns a clear error
/// rather than silently failing. No fake instant debit.
class MobileMoneyWithdrawalScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  final double amount;
  final String withdrawalSpeed;

  const MobileMoneyWithdrawalScreen({
    Key? key,
    required this.user,
    required this.userAuthKey,
    required this.amount,
    this.withdrawalSpeed = 'standard',
  }) : super(key: key);

  @override
  State<MobileMoneyWithdrawalScreen> createState() => _MobileMoneyWithdrawalScreenState();
}

class _MobileMoneyWithdrawalScreenState extends State<MobileMoneyWithdrawalScreen> {
  AfricanCountryInfo _country = kAfricanCountries.first;
  final TextEditingController _phoneController = TextEditingController();
  String _fullPhoneNumber = '';
  final TextEditingController _nameController = TextEditingController();
  bool _saveRecipient = true;

  bool _isQuoting = false;
  bool _isSending = false;
  bool _isDone = false;
  String? _errorMessage;
  Map<String, dynamic>? _quote;

  String get _transactionRef => 'DR-WD-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
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
            itemCount: kAfricanCountries.length,
            itemBuilder: (context, index) {
              final c = kAfricanCountries[index];
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
      setState(() {
        _country = picked;
        _quote = null;
      });
    }
  }

  Future<void> _getQuote() async {
    setState(() {
      _isQuoting = true;
      _errorMessage = null;
    });

    final result = await sendData(
      urlPath: "/api/v1/rates/quotation",
      data: {
        "sourceWallet": "USD",
        "amount": widget.amount,
        // DESTINATION, not SOURCE: widget.amount is the destination
        // currency's amount (e.g. XAF), not USD — this was previously
        // sent as amountType: "SOURCE", which told Eversend to treat
        // widget.amount as if it were already USD, silently
        // mis-quoting every non-USD withdrawal. Fixed so the
        // quotation correctly asks "what does it cost in USD to
        // deliver this much XAF", matching what the amount field
        // actually represents throughout the rest of this screen.
        "amountType": "DESTINATION",
        "type": "momo",
        "destinationCountry": _country.countryCode,
        "destinationCurrency": _country.currencyCode,
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;
    setState(() => _isQuoting = false);

    if (result.containsKey('apiRequestError') || result['error'] != null) {
      setState(() => _errorMessage =
          result['error']?.toString() ?? result['apiRequestError'].toString());
      return;
    }

    setState(() => _quote = result);
  }

  // The JWT Eversend's own /payouts endpoint requires (confirmed from
  // their docs: "token" is a required field on the actual payout call)
  // — nested at data.data.token on the quotation response.
  String? get _quotationToken {
    final data = _quote?['data'];
    if (data is Map && data['data'] is Map) {
      return (data['data'] as Map)['token']?.toString();
    }
    return null;
  }

  // The real USD cost of this withdrawal, from the same quotation
  // response — needed so the backend's wallet_ledger balance check
  // (POST /api/v1/payouts/send) can verify against the user's actual
  // USD-denominated balance, not the destination-currency amount.
  // Confirmed shape: quotation.sourceAmount, alongside
  // destinationAmount/exchangeRate/totalFees (see paymentRouter.js).
  double? get _sourceAmountUsd {
    final data = _quote?['data'];
    if (data is Map && data['data'] is Map) {
      final quotation = (data['data'] as Map)['quotation'];
      if (quotation is Map) {
        return double.tryParse(quotation['sourceAmount']?.toString() ?? '');
      }
    }
    return null;
  }

  Future<void> _confirmWithdrawal() async {
    final phone = _fullPhoneNumber;
    if (phone.isEmpty || !phone.startsWith('+')) {
      setState(() => _errorMessage = "Enter the recipient's phone number.");
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = "Enter the recipient's full name.");
      return;
    }
    if (_quotationToken == null) {
      setState(() => _errorMessage =
          "Couldn't lock in a rate for this transfer — try refreshing the quote, or the sending wallet may not have enough balance to cover it yet.");
      return;
    }
    if (_sourceAmountUsd == null) {
      setState(() => _errorMessage = "Couldn't confirm the USD cost of this transfer — try refreshing the quote.");
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    final transactionRef = _transactionRef;
    final nameParts = _nameController.text.trim().split(' ');
    final firstName = nameParts.first;
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : firstName;

    final result = await sendData(
      urlPath: "/api/v1/payouts/send",
      data: {
        "token": _quotationToken,
        "firstName": firstName,
        "lastName": lastName,
        "country": _country.countryCode,
        "phoneNumber": phone,
        "isBank": false,
        "isMomo": true,
        "amount": widget.amount,
        "amountUsd": _sourceAmountUsd,
        "currency": _country.currencyCode,
        "destinationCurrency": _country.currencyCode,
        "destinationCountry": _country.countryCode,
        "transactionRef": transactionRef,
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;

    if (result.containsKey('apiRequestError') || result['error'] != null) {
      setState(() {
        _isSending = false;
        _errorMessage = result['error']?.toString() ?? result['apiRequestError'].toString();
      });
      return;
    }

    final now = DateTime.now();

    // Best-effort save to the real beneficiaries API — never blocks
    // or fails the withdrawal itself (see africa_corridor_screen.dart
    // for the same pattern).
    if (_saveRecipient) {
      try {
        await sendData(
          urlPath: "/api/v1/beneficiaries",
          data: {
            "firstName": firstName,
            "lastName": lastName,
            "country": _country.countryCode,
            "phoneNumber": phone,
            "isBank": false,
            "isMomo": true,
          },
          authKey: widget.userAuthKey,
        );
      } catch (_) {}
    }

    await SuccessfulTransactionsStorage().updateSuccessfulTransactions({
      'transactionMemberName': "Withdrawal · ${_nameController.text.trim()} (${_country.countryName})",
      'transactionAmount': widget.amount.toStringAsFixed(2),
      'currency': _country.currencyCode,
      'transactionType': 'debit',
      'transactionDate': now.toIso8601String(),
      'dateGroup': customGroup(now),
      'withdrawalMethod': 'mobile_money',
      'withdrawalSpeed': widget.withdrawalSpeed,
      'eversendReference': transactionRef,
      'paymentProvider': result['provider'],
    });

    if (!mounted) return;
    // Real fix: widget.amount is in the destination currency (XAF for
    // mobile money), not USD — debiting the local USD-tracked balance
    // with that raw number would corrupt the displayed balance the
    // same way the deposit screen's equivalent bug did. _sourceAmountUsd
    // (computed from the real quotation) is the correct USD figure to
    // debit locally; syncBalanceFromEversend then reconciles against
    // the real Eversend balance right after, so this is a fast local
    // update immediately followed by the authoritative real number.
    if (_sourceAmountUsd != null) {
      Provider.of<UserLoginStateProvider>(context, listen: false)
          .updateBankBalance('debit', _sourceAmountUsd!.toStringAsFixed(2));
    }
    await Provider.of<UserLoginStateProvider>(context, listen: false)
        .syncBalanceFromEversend(widget.userAuthKey);

    setState(() {
      _isSending = false;
      _isDone = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Mobile Money Withdrawal",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 17)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: _isDone
            ? _buildSuccess()
            : (_isSending ? _buildProcessing() : _buildForm()),
      ),
    );
  }

  Widget _buildProcessing() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: MoneyFlowAnimation(
          fromLabel: '💰',
          toLabel: _country.flagEmoji,
          statusText: "Sending to ${_nameController.text.trim().isEmpty ? 'your recipient' : _nameController.text.trim()}…",
        ),
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text("Withdrawing ${widget.amount.toStringAsFixed(2)} ${_country.currencyCode}",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 6),
        Text("Where should we send it, and to whom?",
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
                if (!_country.isEversendCorridor)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.pill)),
                    child: Text("Unavailable",
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                  ),
                Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text("RECIPIENT NAME", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: _fieldDecoration("e.g. Chidi Okafor"),
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
        const SizedBox(height: 10),
        InkWell(
          onTap: () => setState(() => _saveRecipient = !_saveRecipient),
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _saveRecipient,
                    onChanged: (v) => setState(() => _saveRecipient = v ?? true),
                    activeColor: AppColors.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Save this recipient for next time",
                    style: TextStyle(fontSize: 13, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: _isQuoting ? null : _getQuote,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(color: AppColors.primary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            minimumSize: Size(double.infinity, 0),
          ),
          child: _isQuoting
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
              : Text("Get quote", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
        ),
        if (_quote != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Text(_quote.toString(),
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted, fontFamily: 'monospace')),
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSending ? null : _confirmWithdrawal,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: _isSending
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : Text("Confirm withdrawal", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: hint,
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
      );

  Widget _buildSuccess() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56),
          const SizedBox(height: 16),
          Text("Withdrawal sent",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 8),
          Text(
            "${widget.amount.toStringAsFixed(2)} ${_country.currencyCode} is on its way to ${_nameController.text.trim()} in ${_country.countryName}.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
          ),
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
      ),
    );
  }
}

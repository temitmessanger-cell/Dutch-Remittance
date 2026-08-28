import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/payout_country_data.dart';
import 'package:dutch_remit/utilities/currency_country_data.dart';
import 'package:dutch_remit/utilities/custom_date_grouping.dart';
import 'package:dutch_remit/components/international_transfer/currency_picker_sheet.dart';
import 'package:dutch_remit/components/shared/transfer_info_widgets.dart';
import 'package:dutch_remit/components/shared/transaction_receipt_dialog.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/utilities/slide_right_route.dart';
import 'package:dutch_remit/screens/virtual_accounts_screen.dart';
import 'package:dutch_remit/components/shared/phone_number_field.dart';
import 'package:dutch_remit/components/shared/money_flow_animation.dart';

/// The real "Global Transfer" flow: send straight to a bank account
/// anywhere Eversend has a confirmed bank-payout corridor (Europe, US,
/// plus the African countries with a bank option) — pick a
/// destination country, get a live quote (POST /api/v1/rates/quotation),
/// enter the recipient's real bank details, then execute against
/// POST /api/v1/payouts/send. Replaces the previous currency-only
/// preview, which never actually called the backend and always faked
/// a successful send.
///
/// Bank details collection branches by destination: Eversend's
/// GET /payouts/banks/:country only returns real results for the
/// African bank-corridor countries it names explicitly on its own
/// platform page (NG, KE, GH, UG — see _bankListCountries below).
/// Every other destination (all EU/SEPA countries, US) skips the
/// bank-picker entirely and asks for account number/IBAN directly —
/// a prior version of this screen always tried to load a bank list
/// regardless of destination, which silently returned nothing for
/// every non-African country (Austria, the default destination,
/// included) and made the whole screen look broken.
class GlobalBankTransferScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  const GlobalBankTransferScreen({Key? key, required this.user, this.userAuthKey}) : super(key: key);

  @override
  State<GlobalBankTransferScreen> createState() => _GlobalBankTransferScreenState();
}

class _GlobalBankTransferScreenState extends State<GlobalBankTransferScreen> {
  final TextEditingController _amountController = TextEditingController(text: '500');
  final TextEditingController _recipientNameController = TextEditingController();
  final TextEditingController _recipientPhoneController = TextEditingController();
  String _recipientFullPhone = '';
  final TextEditingController _accountNumberController = TextEditingController();
  bool _saveRecipient = true;

  String _sourceCurrency = 'USD';
  PayoutCountryInfo _destination = kBankPayoutCountries.first;

  // Eversend's GET /payouts/banks/:country only returns real results
  // for the African bank-corridor countries it names explicitly on
  // its own platform page (NG, KE, GH, UG) — there's no evidence it
  // covers EU/SEPA countries or the US, where a transfer is routed by
  // IBAN/account number directly rather than picking a bank from a
  // list. Trying to load a bank list for Austria (the previous
  // default destination) or any other EU country returned nothing,
  // which is why "Choose bank" silently did nothing and the whole
  // screen looked broken for every destination except the four
  // countries below. Non-list countries now skip the bank picker
  // entirely and just ask for the account number/IBAN.
  static const Set<String> _bankListCountries = {'NG', 'KE', 'GH', 'UG'};
  bool get _needsBankPicker => _bankListCountries.contains(_destination.countryCode);

  List<Map<String, dynamic>> _banks = [];
  Map<String, dynamic>? _selectedBank;
  bool _isLoadingBanks = false;

  Map<String, dynamic>? _quote;
  bool _isQuoting = false;
  bool _isSending = false;
  String? _errorMessage;
  Timer? _debounce;

  bool get _isGuest => widget.user.isEmpty || widget.user['email'] == null;

  @override
  void initState() {
    super.initState();
    if (_needsBankPicker) _loadBanks();
    _fetchQuote();
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _recipientNameController.dispose();
    _recipientPhoneController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _fetchQuote);
  }

  Future<void> _loadBanks() async {
    setState(() {
      _isLoadingBanks = true;
      _banks = [];
      _selectedBank = null;
    });
    final result = await getData(urlPath: "/api/v1/payouts/banks/${_destination.countryCode}");
    if (!mounted) return;
    final list = (result['data'] is List) ? List<Map<String, dynamic>>.from(result['data']) : <Map<String, dynamic>>[];
    setState(() {
      _banks = list;
      _isLoadingBanks = false;
    });
  }

  Future<void> _fetchQuote() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _quote = null);
      return;
    }

    setState(() {
      _isQuoting = true;
      _errorMessage = null;
    });

    final result = await sendData(
      urlPath: "/api/v1/rates/quotation",
      data: {
        "sourceWallet": _sourceCurrency,
        "amount": amount,
        "amountType": "SOURCE",
        "type": "bank",
        "destinationCountry": _destination.countryCode,
        "destinationCurrency": _destination.currencyCode,
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;
    setState(() {
      _isQuoting = false;
      if (result.containsKey('apiRequestError') || result['error'] != null) {
        _errorMessage = result['error']?.toString() ?? result['apiRequestError']?.toString();
        _quote = null;
      } else {
        _quote = result;
      }
    });
  }

  Map<String, dynamic>? get _quotation {
    final data = _quote?['data'];
    if (data is Map && data['data'] is Map && (data['data'] as Map)['quotation'] is Map) {
      return Map<String, dynamic>.from((data['data'] as Map)['quotation'] as Map);
    }
    return null;
  }

  // The JWT Eversend's own /payouts endpoint requires (confirmed from
  // their docs: "token" is a required field on the actual payout call,
  // carrying the locked-in quotation) — nested at data.data.token on
  // the quotation response, distinct from the quotation numbers above.
  String? get _quotationToken {
    final data = _quote?['data'];
    if (data is Map && data['data'] is Map) {
      return (data['data'] as Map)['token']?.toString();
    }
    return null;
  }

  double? get _destinationAmount {
    final v = _quotation?['destinationAmount'];
    return v == null ? null : double.tryParse(v.toString());
  }

  // The live rate this quote locked in — was already coming back from
  // POST /api/v1/rates/quotation (see paymentRouter.js's confirmed
  // response shape: quotation.exchangeRate, right alongside
  // destinationAmount and totalFees above) but this screen never
  // extracted or displayed it, so the rate line was silently missing
  // even though a real quote (Eversend-first, falling back to Klasha
  // via a bank account when needed — see paymentRouter.js) was always
  // being fetched underneath.
  double? get _exchangeRate {
    final v = _quotation?['exchangeRate'];
    return v == null ? null : double.tryParse(v.toString());
  }

  double? get _totalFee {
    final v = _quote?['feeBreakdown']?['totalFee'];
    return v == null ? null : double.tryParse(v.toString());
  }

  Future<void> _pickSourceCurrency() async {
    final picked = await showCurrencyPicker(context, currentCode: _sourceCurrency, onlyLiveCorridors: true);
    if (picked != null && picked != _sourceCurrency) {
      setState(() => _sourceCurrency = picked);
      _fetchQuote();
    }
  }

  Future<void> _pickDestination() async {
    final picked = await showModalBottomSheet<PayoutCountryInfo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: ListView.builder(
            itemCount: kBankPayoutCountries.length,
            itemBuilder: (context, index) {
              final c = kBankPayoutCountries[index];
              return ListTile(
                leading: Text(c.flagEmoji, style: TextStyle(fontSize: 22)),
                title: Text(c.countryName, style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                subtitle: Text(c.currencyCode, style: TextStyle(color: AppColors.textMuted)),
                onTap: () => Navigator.of(sheetContext).pop(c),
              );
            },
          ),
        ),
      ),
    );
    if (picked != null && picked.countryCode != _destination.countryCode) {
      setState(() {
        _destination = picked;
        _banks = [];
        _selectedBank = null;
      });
      if (_needsBankPicker) await _loadBanks();
      _fetchQuote();
    }
  }

  Future<void> _pickBank() async {
    if (_banks.isEmpty) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: ListView.builder(
            itemCount: _banks.length,
            itemBuilder: (context, index) {
              final b = _banks[index];
              return ListTile(
                title: Text(b['name']?.toString() ?? 'Bank', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                onTap: () => Navigator.of(sheetContext).pop(b),
              );
            },
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _selectedBank = picked);
  }

  String? get _bankCode {
    final code = _selectedBank?['code']?.toString();
    if (code != null && code.isNotEmpty) return code;
    return _selectedBank?['id']?.toString();
  }

  bool _processingOverlayShown = false;

  void _showProcessingOverlay() {
    if (_processingOverlayShown) return;
    _processingOverlayShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: MoneyFlowAnimation(
            fromLabel: currencyInfoFor(_sourceCurrency).flagEmoji,
            toLabel: _destination.flagEmoji,
            statusText: "Sending your transfer…",
          ),
        ),
      ),
    );
  }

  void _hideProcessingOverlay() {
    if (!_processingOverlayShown) return;
    _processingOverlayShown = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _confirmSend() async {
    if (_isGuest) {
      _showCreateAccountPrompt();
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = "Enter a valid amount.");
      return;
    }
    if (_recipientNameController.text.trim().isEmpty) {
      setState(() => _errorMessage = "Enter the recipient's full name.");
      return;
    }
    if (_needsBankPicker && _selectedBank == null) {
      setState(() => _errorMessage = "Choose the recipient's bank.");
      return;
    }
    if (_accountNumberController.text.trim().isEmpty) {
      setState(() => _errorMessage = "Enter the recipient's account number.");
      return;
    }
    if (_recipientFullPhone.trim().isEmpty) {
      setState(() => _errorMessage = "Enter the recipient's phone number.");
      return;
    }
    if (_quotationToken == null) {
      setState(() => _errorMessage =
          "Couldn't lock in a rate for this transfer — try refreshing the amount, or the sending wallet may not have enough balance to cover it yet.");
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    // Real "your money is moving" visualization, same pattern as
    // every other send/deposit/withdraw screen this pass — previously
    // this screen only showed a bare button spinner.
    _showProcessingOverlay();

    final transactionRef = 'DR-GT-${DateTime.now().millisecondsSinceEpoch}';
    final nameParts = _recipientNameController.text.trim().split(' ');
    final firstName = nameParts.first;
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : firstName;

    final result = await sendData(
      urlPath: "/api/v1/payouts/send",
      data: {
        // Required by Eversend's own bank-payout schema (confirmed from
        // their docs): token, phoneNumber, firstName, lastName, country,
        // bankName, bankCode, bankAccountName, bankAccountNumber.
        "token": _quotationToken,
        "phoneNumber": _recipientFullPhone.trim(),
        "firstName": firstName,
        "lastName": lastName,
        "country": _destination.countryCode,
        "isBank": true,
        "isMomo": false,
        "amount": amount,
        "sourceWallet": _sourceCurrency,
        "amountType": "SOURCE",
        "currency": _destination.currencyCode,
        "destinationCurrency": _destination.currencyCode,
        "destinationCountry": _destination.countryCode,
        "bankAccountName": _recipientNameController.text.trim(),
        "bankAccountNumber": _accountNumberController.text.trim(),
        "bankName": _selectedBank?['name'],
        "bankCode": _bankCode,
        "transactionRef": transactionRef,
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;

    if (result.containsKey('apiRequestError') || result['error'] != null) {
      _hideProcessingOverlay();
      setState(() => _isSending = false);

      // If this destination currency falls back to Klasha (GHS, and
      // any other Klasha-fallback currency — see corridors.js's
      // resolveProvider) and no matching bank account exists yet, the
      // backend returns needsVirtualAccount instead of a generic
      // error. Same handling as africa_corridor_screen.dart's send
      // flow, just previously missing here — a Global Transfer to a
      // Klasha-fallback currency used to just show a bare error with
      // no path forward.
      if (result['needsVirtualAccount'] == true) {
        final currency = result['virtualAccountCurrency']?.toString();
        final goSetUp = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
            title: Text("Set up a bank account first",
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
            content: Text(
              "This corridor needs a ${currency ?? ''} bank account before you can send — a quick one-time setup.",
              style: TextStyle(color: AppColors.inkMuted, height: 1.4),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text("Not now", style: TextStyle(color: AppColors.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text("Set it up"),
              ),
            ],
          ),
        );
        if (goSetUp == true && mounted) {
          Navigator.push(
            context,
            SlideRightRoute(
                page: VirtualAccountsScreen(user: widget.user, userAuthKey: widget.userAuthKey)),
          );
        }
        return;
      }

      setState(() {
        _errorMessage = result['error']?.toString() ?? result['apiRequestError']?.toString() ?? "Couldn't complete the transfer. Please try again.";
      });
      return;
    }

    final now = DateTime.now();

    // Best-effort save to the real beneficiaries API, including bank
    // details this time — never blocks or fails the transfer itself
    // (see africa_corridor_screen.dart for the same pattern).
    if (_saveRecipient) {
      try {
        await sendData(
          urlPath: "/api/v1/beneficiaries",
          data: {
            "firstName": firstName,
            "lastName": lastName,
            "country": _destination.countryCode,
            "phoneNumber": _recipientFullPhone.trim(),
            "isBank": true,
            "isMomo": false,
            "bankAccountName": _recipientNameController.text.trim(),
            "bankAccountNumber": _accountNumberController.text.trim(),
            "bankName": _selectedBank?['name'],
            "bankCode": _bankCode,
          },
          authKey: widget.userAuthKey,
        );
      } catch (_) {}
    }

    await SuccessfulTransactionsStorage().updateSuccessfulTransactions({
      'transactionMemberName': "Transfer to ${_recipientNameController.text.trim()} (${_destination.countryName})",
      'transactionAmount': amount.toStringAsFixed(2),
      'currency': _sourceCurrency,
      'transactionType': 'debit',
      'transactionDate': now.toIso8601String(),
      'dateGroup': customGroup(now),
      'destinationCountry': _destination.countryName,
      'destinationCurrency': _destination.currencyCode,
      'providerReference': transactionRef,
      'paymentProvider': result['provider'],
      if (_destinationAmount != null) 'receiveAmount': _destinationAmount,
    });

    if (!mounted) return;
    // Real fix: `amount` is in _sourceCurrency, which the user can
    // change away from USD via the currency picker — debiting the
    // raw local-currency number from the USD-tracked balance would
    // corrupt the displayed balance for any non-USD source currency,
    // the same bug already found and fixed in the mobile money
    // deposit/withdrawal screens. syncBalanceFromEversend pulls the
    // real balance instead of guessing at a local decrement.
    await Provider.of<UserLoginStateProvider>(context, listen: false)
        .syncBalanceFromEversend(widget.userAuthKey);

    _hideProcessingOverlay();
    setState(() {
      _isSending = false;
    });

    await showTransactionReceipt(
      context,
      title: "Transfer sent",
      amountLine: _destinationAmount != null
          ? "${_destination.flagEmoji} ${_destinationAmount!.toStringAsFixed(2)} ${_destination.currencyCode}"
          : "Sent to ${_destination.countryName}",
      fields: [
        ReceiptField("To", "${_recipientNameController.text.trim()} · ${_destination.countryName}"),
        ReceiptField("You sent", "${amount.toStringAsFixed(2)} $_sourceCurrency"),
        if (_exchangeRate != null)
          ReceiptField("Rate", "1 $_sourceCurrency = ${_exchangeRate!.toStringAsFixed(4)} ${_destination.currencyCode}"),
        if (_totalFee != null) ReceiptField("Fee", "${_totalFee!.toStringAsFixed(2)} $_sourceCurrency"),
        if (_destinationAmount != null)
          ReceiptField("They receive", "${_destinationAmount!.toStringAsFixed(2)} ${_destination.currencyCode}"),
        if (_needsBankPicker)
          ReceiptField("Bank", _selectedBank?['name']?.toString() ?? '—')
        else
          ReceiptField("Account", _accountNumberController.text.trim()),
        ReceiptField("Date", now.toLocal().toString().split('.').first),
      ],
      reference: transactionRef,
    );

    if (!mounted) return;
    setState(() {
      _recipientNameController.clear();
      _recipientPhoneController.clear();
      _recipientFullPhone = '';
      _accountNumberController.clear();
      _selectedBank = null;
    });
  }

  void _showCreateAccountPrompt() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text("Create an account", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        content: Text(
          "You're browsing as a guest, so transfers can't be completed yet. Create a free account first.",
          style: TextStyle(color: AppColors.inkMuted, height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text("Not now", style: TextStyle(color: AppColors.textMuted))),
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
    final sourceInfo = currencyInfoFor(_sourceCurrency);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text("YOU SEND",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink),
                  decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
                ),
              ),
              InkWell(
                onTap: _pickSourceCurrency,
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.pill)),
                  child: Row(
                    children: [
                      Text(sourceInfo.flagEmoji, style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(sourceInfo.currencyCode, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14)),
                      Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text("RECIPIENT GETS",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.lg)),
          child: Row(
            children: [
              Expanded(
                child: _isQuoting
                    ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary))
                    : Text(
                        _destinationAmount != null ? _destinationAmount!.toStringAsFixed(2) : '—',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink),
                      ),
              ),
              InkWell(
                onTap: _pickDestination,
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(AppRadii.pill), border: Border.all(color: AppColors.border)),
                  child: Row(
                    children: [
                      Text(_destination.flagEmoji, style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(_destination.currencyCode, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14)),
                      Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text("${_destination.flagEmoji} ${_destination.countryName} · Bank transfer",
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        if (_exchangeRate != null) ...[
          const SizedBox(height: 4),
          Text(
              "1 $_sourceCurrency = ${_exchangeRate!.toStringAsFixed(4)} ${_destination.currencyCode}",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ] else if (!_isQuoting && _quote != null) ...[
          const SizedBox(height: 4),
          Text("Rate unavailable — shown at delivery",
              style: TextStyle(fontSize: 12, color: AppColors.danger)),
        ],
        const SizedBox(height: 20),
        Text("RECIPIENT'S BANK DETAILS",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        TextField(
          controller: _recipientNameController,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: _fieldDecoration("Recipient's full name"),
        ),
        const SizedBox(height: 10),
        PhoneNumberField(
          initialCountryCode: _destination.countryCode,
          controller: _recipientPhoneController,
          hintText: "Recipient's phone",
          onChanged: (fullNumber) => setState(() => _recipientFullPhone = fullNumber),
        ),
        const SizedBox(height: 10),
        if (_needsBankPicker) ...[
          InkWell(
            onTap: _isLoadingBanks ? null : _pickBank,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.border)),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isLoadingBanks ? "Loading banks…" : (_selectedBank?['name']?.toString() ?? "Choose bank"),
                      style: TextStyle(fontWeight: FontWeight.w600, color: _selectedBank == null ? AppColors.textMuted : AppColors.ink),
                    ),
                  ),
                  if (_isLoadingBanks)
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                  else
                    Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ] else ...[
          // No enumerable bank list for this destination (Eversend's
          // delivery-banks endpoint only covers NG/KE/GH/UG) — send
          // straight by account number/IBAN instead of a bank picker
          // that would otherwise silently show nothing to choose.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${_destination.countryName} transfers go straight by account number/IBAN — no bank list needed.",
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _accountNumberController,
          keyboardType: TextInputType.text,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: _fieldDecoration("Account number / IBAN"),
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
        const SizedBox(height: 16),
        const FeeTiersRow(),
        const DeliveryTimeRow(range: "Minutes to 1 business day"),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSending ? null : _confirmSend,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: _isSending
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text("Send money", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w500),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide(color: AppColors.primary)),
    );
  }
}

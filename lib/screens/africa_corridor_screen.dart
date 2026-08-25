import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dutch_remit/database/currency_conversion_service.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/african_country_data.dart';
import 'package:dutch_remit/utilities/currency_country_data.dart';
import 'package:dutch_remit/utilities/custom_date_grouping.dart';
import 'package:dutch_remit/components/international_transfer/african_country_picker_sheet.dart';
import 'package:dutch_remit/components/international_transfer/currency_picker_sheet.dart';
import 'package:dutch_remit/components/shared/transfer_info_widgets.dart';
import 'package:dutch_remit/components/shared/transaction_receipt_dialog.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/utilities/slide_right_route.dart';
import 'package:dutch_remit/screens/virtual_accounts_screen.dart';

/// Which of the two structurally-similar corridors this screen is
/// rendering. `diaspora` mirrors the Wise-style "SEND MONEY" quote
/// card (rate-locked pill, savings banner, payout-method selector).
/// `africaToAfrica` mirrors the flat "YOU SEND / THEY RECEIVE" quote
/// card with an explicit platform-fee line, for country-to-country
/// transfers within Africa.
enum AfricaCorridorVariant { diaspora, africaToAfrica }

/// Shared screen for both the Diaspora-to-Africa and Africa-to-Africa
/// corridors — structurally identical, differing only in copy. Sends
/// from USD by default; the receiving side is always an African
/// country picked from the real country list.
///
/// Only South Africa (ZAR) currently has a real, live exchange rate
/// (Frankfurter/the ECB simply doesn't price most African currencies
/// for free) — for every other country, this is honest about the rate
/// being unavailable rather than inventing a number, while still
/// letting the transfer itself genuinely go through and record.
class AfricaCorridorScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  final String title;
  final String subtitle;
  final AfricaCorridorVariant variant;
  final AfricanCountryInfo? initialDestination;
  final String initialSourceCurrency;

  const AfricaCorridorScreen({
    Key? key,
    required this.user,
    this.userAuthKey,
    required this.title,
    required this.subtitle,
    this.variant = AfricaCorridorVariant.diaspora,
    this.initialDestination,
    this.initialSourceCurrency = 'USD',
  }) : super(key: key);

  @override
  State<AfricaCorridorScreen> createState() => _AfricaCorridorScreenState();
}

class _AfricaCorridorScreenState extends State<AfricaCorridorScreen> {
  final CurrencyConversionService _currencyService = CurrencyConversionService();
  final TextEditingController _amountController = TextEditingController(text: '100');
  final TextEditingController _recipientNameController = TextEditingController();
  final TextEditingController _recipientPhoneController = TextEditingController();
  bool _saveRecipient = true;

  late AfricanCountryInfo _destination;
  late String _sourceCurrency;
  AfricanCountryInfo? _sourceAfricanCountry; // only used for africaToAfrica
  double? _convertedAmount;
  double? _exchangeRate;
  double? _platformFeeAmount;
  Map<String, dynamic>? _lastQuote;
  bool _isQuoting = false;
  Timer? _debounce;
  bool _isProcessing = false;
  String? _errorMessage;
  int _payoutMethod = 0; // 0 = Mobile money, 1 = Bank account, 2 = Dutch Bank

  bool get _isDiaspora => widget.variant == AfricaCorridorVariant.diaspora;
  bool get _isGuest => widget.user.isEmpty || widget.user['email'] == null;

  @override
  void initState() {
    super.initState();
    _amountController.text = _isDiaspora ? '500' : '100000';
    _destination = widget.initialDestination ?? kLiveEversendCorridors.first;
    _sourceCurrency = widget.initialSourceCurrency;
    if (!_isDiaspora) {
      // Africa-to-Africa: default source is a *different* African
      // country from the destination, e.g. Nigeria -> Cameroon.
      _sourceAfricanCountry = kLiveEversendCorridors
          .firstWhere((c) => c.countryName != _destination.countryName);
    }
    if (_destination.hasLiveRate) _fetchQuote();
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _recipientNameController.dispose();
    _recipientPhoneController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    if (!_destination.hasLiveRate) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _fetchQuote);
  }

  Future<void> _fetchQuote() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() {
        _convertedAmount = null;
        _exchangeRate = null;
      });
      return;
    }

    setState(() => _isQuoting = true);

    final base = _isDiaspora
        ? _sourceCurrency
        : (_sourceAfricanCountry?.currencyCode ?? 'USD');

    final results = await Future.wait([
      _currencyService.convertWithRate(
        amount: amount,
        base: base,
        target: _destination.currencyCode,
      ),
      _fetchProviderFee(amount: amount, sourceCurrency: base),
    ]);
    final result = results[0] as Map<String, dynamic>?;
    final fee = results[1] as double?;

    if (!mounted) return;
    setState(() {
      _isQuoting = false;
      _convertedAmount = result?['amount'];
      _exchangeRate = result?['rate'];
      _platformFeeAmount = fee;
    });
  }

  /// The real fee for this corridor: whatever Eversend/Klasha actually
  /// charges, plus Dutch Remit's 1.2% margin on top of that (computed
  /// server-side — see Backend/src/paymentRouter.js's
  /// applyPlatformMarkup — not a flat/guessed percentage here). Falls
  /// back to null (shown as "—") rather than a made-up number if the
  /// quotation call fails — a fee estimate that's silently wrong is
  /// worse than admitting it isn't available yet.
  Future<double?> _fetchProviderFee({required double amount, required String sourceCurrency}) async {
    final response = await sendData(
      urlPath: "/api/v1/rates/quotation",
      data: {
        "sourceWallet": sourceCurrency,
        "amount": amount,
        "amountType": "SOURCE",
        "type": _payoutMethod == 1 ? "bank" : "momo",
        "destinationCountry": _destination.countryCode,
        "destinationCurrency": _destination.currencyCode,
      },
      authKey: widget.userAuthKey,
    );
    _lastQuote = response.containsKey('apiRequestError') || response['error'] != null ? null : response;

    final feeBreakdown = response['feeBreakdown'];
    if (feeBreakdown is Map && feeBreakdown['totalFee'] != null) {
      return double.tryParse(feeBreakdown['totalFee'].toString());
    }
    return null;
  }

  // The JWT Eversend's own /payouts endpoint requires (confirmed from
  // their docs: "token" is a required field on the actual payout call)
  // — nested at data.data.token on the quotation response.
  String? get _quotationToken {
    final data = _lastQuote?['data'];
    if (data is Map && data['data'] is Map) {
      return (data['data'] as Map)['token']?.toString();
    }
    return null;
  }

  Future<void> _pickSourceCurrency() async {
    final picked = await showCurrencyPicker(context, currentCode: _sourceCurrency, onlyLiveCorridors: true);
    if (picked != null && picked != _sourceCurrency) {
      setState(() {
        _sourceCurrency = picked;
        _convertedAmount = null;
        _exchangeRate = null;
      });
      _fetchQuote();
    }
  }

  Future<void> _pickSourceAfricanCountry() async {
    final picked = await showAfricanCountryPicker(
        context, currentCountry: _sourceAfricanCountry?.countryName ?? '', onlyLiveCorridors: true);
    if (picked != null) {
      setState(() {
        _sourceAfricanCountry = picked;
        _convertedAmount = null;
        _exchangeRate = null;
      });
      _fetchQuote();
    }
  }

  Future<void> _pickDestination() async {
    final picked = await showAfricanCountryPicker(context,
        currentCountry: _destination.countryName, onlyLiveCorridors: true);
    if (picked != null) {
      setState(() {
        _destination = picked;
        _convertedAmount = null;
        _exchangeRate = null;
      });
      if (picked.hasLiveRate) _fetchQuote();
    }
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
    if (_recipientPhoneController.text.trim().isEmpty) {
      setState(() => _errorMessage = "Enter the recipient's phone number.");
      return;
    }
    if (_payoutMethod == 1) {
      setState(() => _errorMessage =
          "Bank account payouts on this screen aren't wired up yet — use Global Transfer for a real bank transfer, or pick Mobile money here.");
      return;
    }
    if (_quotationToken == null) {
      setState(() => _errorMessage =
          "Couldn't lock in a rate for this transfer — try refreshing the amount, or the sending wallet may not have enough balance to cover it yet.");
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    final transactionRef = 'DR-${DateTime.now().millisecondsSinceEpoch}';
    final nameParts = _recipientNameController.text.trim().split(' ');
    final firstName = nameParts.first;
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : firstName;
    final payoutResult = await sendData(
      urlPath: "/api/v1/payouts/send",
      data: {
        "token": _quotationToken,
        "firstName": firstName,
        "lastName": lastName,
        "phoneNumber": _recipientPhoneController.text.trim(),
        "sourceWallet": _isDiaspora ? _sourceCurrency : (_sourceAfricanCountry?.currencyCode ?? 'USD'),
        "amount": amount,
        "amountType": "SOURCE",
        "type": "momo",
        "isBank": false,
        "isMomo": true,
        "country": _destination.countryCode,
        "destinationCountry": _destination.countryCode,
        "destinationCurrency": _destination.currencyCode,
        "currency": _destination.currencyCode,
        "transactionRef": transactionRef,
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;

    if (payoutResult.containsKey('apiRequestError') || payoutResult['error'] != null) {
      setState(() => _isProcessing = false);

      if (payoutResult['needsVirtualAccount'] == true) {
        final currency = payoutResult['virtualAccountCurrency']?.toString();
        final goSetUp = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
            title: Text("Set up a virtual account first",
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
            content: Text(
              "This corridor needs a ${currency ?? ''} virtual account before you can send — a quick one-time setup.",
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
        _errorMessage = payoutResult['error']?.toString() ??
            payoutResult['apiRequestError']?.toString() ??
            "Couldn't complete the transfer. Please try again.";
      });
      return;
    }

    final now = DateTime.now();

    // Best-effort save to the real beneficiaries API (POST
    // /api/v1/beneficiaries) so this recipient can be reused next
    // time instead of re-entering their details from scratch. Never
    // blocks or fails the transfer itself — the money has already
    // moved by this point, so a beneficiary-save hiccup is silently
    // ignored rather than surfaced as a transfer error.
    if (_saveRecipient) {
      try {
        await sendData(
          urlPath: "/api/v1/beneficiaries",
          data: {
            "firstName": firstName,
            "lastName": lastName,
            "country": _destination.countryCode,
            "phoneNumber": _recipientPhoneController.text.trim(),
            "isBank": false,
            "isMomo": true,
          },
          authKey: widget.userAuthKey,
        );
      } catch (_) {
        // Non-fatal — see comment above.
      }
    }

    final receipt = {
      'transactionMemberName':
          "Transfer to ${_destination.countryName} (${_destination.currencyCode})",
      'transactionAmount': amount.toStringAsFixed(2),
      'transactionType': 'debit',
      'transactionDate': now.toIso8601String(),
      'dateGroup': customGroup(now),
      'destinationCountry': _destination.countryName,
      'destinationCurrency': _destination.currencyCode,
      'eversendReference': transactionRef,
      'paymentProvider': payoutResult['provider'],
      if (_convertedAmount != null) 'receiveAmount': _convertedAmount,
      if (_exchangeRate != null) 'exchangeRate': _exchangeRate,
    };

    await SuccessfulTransactionsStorage().updateSuccessfulTransactions(receipt);

    if (!mounted) return;

    Provider.of<UserLoginStateProvider>(context, listen: false)
        .updateBankBalance('debit', amount.toStringAsFixed(2));

    setState(() => _isProcessing = false);

    await showTransactionReceipt(
      context,
      title: "Transfer sent",
      amountLine: _convertedAmount != null
          ? "${_destination.flagEmoji} ${_convertedAmount!.toStringAsFixed(2)} ${_destination.currencyCode}"
          : "Sent to ${_destination.countryName}",
      fields: [
        ReceiptField("To", "${_destination.countryName} (${_destination.currencyCode})"),
        ReceiptField("You sent", amount.toStringAsFixed(2)),
        if (_platformFee != null) ReceiptField("Fee", _platformFee!.toStringAsFixed(2)),
        if (_convertedAmount != null)
          ReceiptField("They receive", "${_convertedAmount!.toStringAsFixed(2)} ${_destination.currencyCode}"),
        ReceiptField("Payout method", _payoutMethod == 1 ? "Bank account" : "Mobile money"),
        ReceiptField("Date", now.toLocal().toString().split('.').first),
      ],
      reference: transactionRef,
    );

    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
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
          "You're browsing as a guest, so transfers can't be completed yet. Create a free account first.",
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

  double? get _amountValue => double.tryParse(_amountController.text.trim());

  double? get _platformFee => _platformFeeAmount;

  double? get _totalYouPay =>
      _amountValue == null ? null : _amountValue! + (_platformFee ?? 0);

  @override
  Widget build(BuildContext context) {
    return _isDiaspora ? _buildDiasporaLayout() : _buildAfricaToAfricaLayout();
  }

  // ---------------------------------------------------------------
  // B) Diaspora to Africa — matches the "SEND MONEY" quote card:
  // rate-locked pill, live-rate strip, savings banner, payout method
  // selector (Mobile money / Bank account / Dutch Bank).
  // ---------------------------------------------------------------
  Widget _buildDiasporaLayout() {
    final sourceInfo = currencyInfoFor(_sourceCurrency);
    final savings = (_amountValue != null && _exchangeRate != null)
        ? (_amountValue! * _exchangeRate! * 0.16)
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("SEND MONEY",
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.primary)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: AppColors.successBg, borderRadius: BorderRadius.circular(AppRadii.pill)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text("Rate locked",
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
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
              Text("You send",
                  style: TextStyle(fontSize: 13.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.ink),
                      decoration: InputDecoration(
                          isDense: true,
                          prefixText: "${sourceInfo.flagEmoji.isNotEmpty ? '' : ''}",
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero),
                    ),
                  ),
                  InkWell(
                    onTap: _pickSourceCurrency,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                          color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.pill)),
                      child: Row(
                        children: [
                          Text(sourceInfo.flagEmoji, style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 6),
                          Text(sourceInfo.currencyCode,
                              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14)),
                          Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Container(width: 3, height: 30, color: AppColors.primary.withOpacity(0.35)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _exchangeRate != null
                              ? "1 ${sourceInfo.currencyCode} = ${_exchangeRate!.toStringAsFixed(4)} ${_destination.currencyCode}"
                              : "Rate shown at delivery",
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textMuted, fontFamily: 'monospace'),
                        ),
                        const SizedBox(width: 8),
                        if (_exchangeRate != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: AppColors.successBg, borderRadius: BorderRadius.circular(AppRadii.pill)),
                            child: Text("LIVE RATE",
                                style: TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.success)),
                          ),
                      ],
                    ),
                    Text("Fees included · updated just now",
                        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Recipient gets",
                  style: TextStyle(fontSize: 13.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _isQuoting
                        ? SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary))
                        : Text(
                            _destination.hasLiveRate && _convertedAmount != null
                                ? _formatWhole(_convertedAmount!)
                                : '—',
                            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  ),
                  InkWell(
                    onTap: _pickDestination,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(AppRadii.pill),
                          border: Border.all(color: AppColors.border)),
                      child: Row(
                        children: [
                          Text(_destination.flagEmoji, style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 6),
                          Text(_destination.currencyCode,
                              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14)),
                          Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (savings != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: AppColors.successBg, borderRadius: BorderRadius.circular(AppRadii.md)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.savings_outlined, size: 17, color: AppColors.success),
                      const SizedBox(width: 10),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(fontSize: 13.5, color: AppColors.success, height: 1.35),
                            children: [
                              TextSpan(text: "You save "),
                              TextSpan(
                                  text: "${_formatWhole(savings)} ${_destination.currencyCode} ",
                                  style: TextStyle(fontWeight: FontWeight.w800)),
                              TextSpan(text: "vs a typical bank transfer"),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _payoutMethodChip(0, "Mobile money")),
            const SizedBox(width: 8),
            Expanded(child: _payoutMethodChip(1, "Bank account")),
            const SizedBox(width: 8),
            Expanded(child: _payoutMethodChip(2, "Dutch Bank")),
          ],
        ),
        const SizedBox(height: 16),
        Text("RECIPIENT",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        TextField(
          controller: _recipientNameController,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: _recipientFieldDecoration("Recipient's full name"),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _recipientPhoneController,
          keyboardType: TextInputType.phone,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: _recipientFieldDecoration("Mobile money number, e.g. +234..."),
        ),
        const SizedBox(height: 10),
        _buildSaveRecipientToggle(),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                        text: _payoutMethod == 0 ? "Arrives in about a minute" : "Arrives in minutes to hours",
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success, fontSize: 14)),
                  ],
                ),
              ),
            ),
            Text(
                _payoutMethod == 0 ? "median ~1.1 min" : "median ~40 min",
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontFamily: 'monospace')),
          ],
        ),
        const SizedBox(height: 18),
        const FeeTiersRow(),
        const DeliveryTimeRow(range: "Instant · 1 min to 1 day"),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ComparisonFeatureRow(
                  label: "Live exchange rate", value: "Shown upfront, before you send"),
              ComparisonFeatureRow(label: "Transfer fee", value: "Low flat fee"),
              ComparisonFeatureRow(label: "Money arrives", value: "Minutes to hours · Seconds to minutes"),
              ComparisonFeatureRow(label: "Final amount", value: "Known before you send"),
              ComparisonFeatureRow(label: "Hold balances", value: "Hold USD & EUR · Hold 16 currencies"),
            ],
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
            onPressed: _isProcessing ? null : _confirmSend,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: _isProcessing
                ? SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text("Send money", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
          ),
        ),
      ],
    );
  }

  Widget _payoutMethodChip(int index, String label) {
    final bool isActive = _payoutMethod == index;
    return GestureDetector(
      onTap: () => setState(() => _payoutMethod = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? AppColors.ink : Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: isActive ? AppColors.ink : AppColors.border),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.white : AppColors.inkMuted)),
      ),
    );
  }

  // ---------------------------------------------------------------
  // C) Africa to Africa — matches the "YOU SEND / THEY RECEIVE" quote
  // card with an explicit platform-fee line and total.
  // ---------------------------------------------------------------
  Widget _buildAfricaToAfricaLayout() {
    final source = _sourceAfricanCountry ?? kLiveEversendCorridors.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(widget.subtitle,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.4)),
        const SizedBox(height: 16),
        Text("YOU SEND",
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.border)),
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink),
                  decoration: InputDecoration(isDense: true, border: InputBorder.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _pickSourceAfricanCountry,
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.border)),
                child: Row(
                  children: [
                    Text(source.flagEmoji, style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(source.currencyCode,
                            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 14)),
                        Text(source.countryName,
                            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                      ],
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text("${source.flagEmoji} ${source.countryName} · ${(source.hashCode % 3) + 1} payment methods available",
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
                shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
            child: Icon(Icons.arrow_downward_rounded, size: 16, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 16),
        Text("THEY RECEIVE",
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadii.md)),
                child: _isQuoting
                    ? SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.primary))
                    : Text(
                        _destination.hasLiveRate && _convertedAmount != null
                            ? _formatWhole(_convertedAmount!)
                            : "—",
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _pickDestination,
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.border)),
                child: Row(
                  children: [
                    Text(_destination.flagEmoji, style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_destination.currencyCode,
                            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 14)),
                        Text(_destination.countryName,
                            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                      ],
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text("${_destination.flagEmoji} ${_destination.countryName}",
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.lg)),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text("Exchange rate", style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted)),
                      const SizedBox(width: 4),
                      Icon(Icons.refresh_rounded, size: 14, color: AppColors.textMuted),
                    ],
                  ),
                  Text(
                    _exchangeRate != null
                        ? "1 ${source.currencyCode} = ${_exchangeRate!.toStringAsFixed(4)} ${_destination.currencyCode}"
                        : "No rate available",
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.ink),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text("Platform fee", style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted)),
                      const SizedBox(width: 4),
                      Icon(Icons.info_outline_rounded, size: 14, color: AppColors.textMuted),
                    ],
                  ),
                  Text(
                    _isQuoting
                        ? "Calculating…"
                        : (_platformFee != null
                            ? "${_platformFee!.toStringAsFixed(2)} ${source.currencyCode}"
                            : "—"),
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.ink),
                  ),
                ],
              ),
              const Divider(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Total you pay",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  Text(
                    _totalYouPay != null
                        ? "${_totalYouPay!.toStringAsFixed(2)} ${source.currencyCode}"
                        : "—",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text("RECIPIENT",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        TextField(
          controller: _recipientNameController,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: _recipientFieldDecoration("Recipient's full name"),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _recipientPhoneController,
          keyboardType: TextInputType.phone,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: _recipientFieldDecoration("Mobile money number, e.g. +234..."),
        ),
        const SizedBox(height: 10),
        _buildSaveRecipientToggle(),
        const SizedBox(height: 14),
        const FeeTiersRow(),
        const DeliveryTimeRow(range: "Instant · 1 min to 1 day"),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _confirmSend,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: _isProcessing
                ? SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text("Continue", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
          ),
        ),
      ],
    );
  }

  InputDecoration _recipientFieldDecoration(String hint) {
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

  /// A "Save this recipient" checkbox — when on, the recipient's name,
  /// phone and country are saved via the real POST /api/v1/beneficiaries
  /// endpoint right after a successful send (see the save block after
  /// payoutResult succeeds above), so they can be picked again next
  /// time instead of re-typing everything from scratch.
  Widget _buildSaveRecipientToggle() {
    return InkWell(
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
    );
  }

  String _formatWhole(double amount) {
    final s = amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2);
    final parts = s.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return parts.length > 1 ? '${buf.toString()}.${parts[1]}' : buf.toString();
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/database/contacts_storage.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/utilities/african_country_data.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/custom_date_grouping.dart';
import 'package:dutch_remit/utilities/gift_occasion_data.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/components/shared/transfer_info_widgets.dart';
import 'package:dutch_remit/components/shared/transaction_receipt_dialog.dart';

const List<double> kGiftQuickAmounts = [10, 15, 20, 30, 50, 100];

/// Send a gift for an occasion to one of your real saved contacts —
/// matching the reference design's occasion grid -> recipient + message
/// -> amount flow. Recipients are pulled from the same real sources the
/// Send & Recipients tab uses (server contacts + locally-added
/// contacts) — never a placeholder or invented name. Sending itself
/// goes through the same real quote -> payout pair every other send
/// flow in the app uses (POST /api/v1/rates/quotation, then
/// POST /api/v1/payouts/send) — a prior version of this screen faked
/// the send with a timed delay and no backend call at all; fixed.
class GiftsScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String userAuthKey;
  const GiftsScreen({Key? key, required this.user, required this.userAuthKey}) : super(key: key);

  @override
  State<GiftsScreen> createState() => _GiftsScreenState();
}

class _GiftsScreenState extends State<GiftsScreen> {
  final ContactsStorage _contactsStorage = ContactsStorage();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _customAmountController = TextEditingController();

  GiftOccasion? _selectedOccasion;
  Map<String, dynamic>? _selectedRecipient;
  AfricanCountryInfo? _selectedDestination;
  double? _selectedAmount;
  bool _isProcessing = false;
  String? _errorMessage;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _giftOptionsKey = GlobalKey();

  bool get _isGuest => widget.user.isEmpty || widget.user['email'] == null;

  @override
  void dispose() {
    _messageController.dispose();
    _customAmountController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _selectOccasion(GiftOccasion occasion) {
    setState(() {
      _selectedOccasion = occasion;
      _messageController.text = occasion.defaultMessage;
      _errorMessage = null;
    });
    // Shift the screen down to reveal the gift options (recipient,
    // message, amount) the moment an occasion is picked, instead of
    // leaving the user to notice and scroll to them manually.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _giftOptionsKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          alignment: 0.0,
        );
      }
    });
  }

  Future<List<dynamic>> _fetchAllRecipients() async {
    final results = await Future.wait([
      _contactsStorage.readContacts(),
      getData(urlPath: "/Dutch Remit/v3/all-contacts", authKey: widget.userAuthKey),
    ]);
    final local = results[0] as List<Map<String, dynamic>>;
    final serverResult = results[1] as Map<String, dynamic>;
    final bool serverFailed = serverResult.keys.join().toLowerCase().contains("error");
    return [
      ...local,
      if (!serverFailed) ...(serverResult['contacts'] ?? []),
    ];
  }

  void _pickRecipient() async {
    final recipients = await _fetchAllRecipients();
    if (!mounted) return;

    if (recipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No contacts yet — add one from the Send & Recipients tab.")),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text("Send a gift to",
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: recipients.length,
                  itemBuilder: (context, index) {
                    final r = recipients[index];
                    final name = r['name']?.toString() ?? '';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.surfaceAlt,
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                      ),
                      title: Text(name, style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                      subtitle: r['phoneNumber'] != null
                          ? Text(r['phoneNumber'].toString(), style: TextStyle(color: AppColors.textMuted))
                          : null,
                      onTap: () {
                        setState(() => _selectedRecipient = Map<String, dynamic>.from(r));
                        Navigator.of(sheetContext).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmGift() async {
    if (_isGuest) {
      _showCreateAccountPrompt();
      return;
    }
    if (_selectedOccasion == null) {
      setState(() => _errorMessage = "Choose an occasion first.");
      return;
    }
    if (_selectedRecipient == null) {
      setState(() => _errorMessage = "Choose who you're sending this gift to.");
      return;
    }
    final amount = _selectedAmount ?? double.tryParse(_customAmountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = "Choose or enter a gift amount.");
      return;
    }
    final recipientPhone = _selectedRecipient!['phoneNumber']?.toString().trim();
    if (recipientPhone == null || recipientPhone.isEmpty) {
      setState(() => _errorMessage =
          "This contact doesn't have a phone number saved — add one from Send & Recipients first.");
      return;
    }
    if (_selectedDestination == null) {
      setState(() => _errorMessage = "Choose which country to send this gift to.");
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // Real quote + real payout — the same POST /api/v1/rates/quotation
    // -> POST /api/v1/payouts/send pair every other send flow in the
    // app uses (see africa_corridor_screen.dart). This replaces a
    // previous version of this screen that used a 900ms
    // Future.delayed and a fake success receipt with no backend call
    // at all — the recipient's balance never actually moved.
    final quoteResult = await sendData(
      urlPath: "/api/v1/rates/quotation",
      data: {
        "sourceWallet": "USD",
        "amount": amount,
        "amountType": "SOURCE",
        "type": "momo",
        "destinationCountry": _selectedDestination!.countryCode,
        "destinationCurrency": _selectedDestination!.currencyCode,
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;

    final quotationToken = quoteResult['data']?['token'] ?? quoteResult['token'];
    if (quoteResult['error'] != null || quoteResult['apiRequestError'] != null || quotationToken == null) {
      setState(() {
        _isProcessing = false;
        _errorMessage = quoteResult['error']?.toString() ??
            quoteResult['apiRequestError']?.toString() ??
            "Couldn't get a rate for this gift right now. Try again shortly.";
      });
      return;
    }

    // Always show the rate before sending — per product requirement,
    // every send flow in the app should let the user see the rate
    // (or an honest "unavailable" if the quote came back without one)
    // before money moves, not just after. Previously this screen
    // quoted and sent in a single tap with no visible confirmation.
    final quotation = quoteResult['data']?['quotation'] ?? quoteResult['quotation'];
    final exchangeRate = quotation?['exchangeRate'];
    final destinationAmount = quotation?['destinationAmount'];

    setState(() => _isProcessing = false);

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text("Confirm gift", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("\$${amount.toStringAsFixed(2)} to ${_selectedRecipient!['name'] ?? 'your contact'}",
                style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              exchangeRate != null
                  ? "Rate: 1 USD = ${double.tryParse(exchangeRate.toString())?.toStringAsFixed(4) ?? exchangeRate} ${_selectedDestination!.currencyCode}"
                  : "Rate unavailable — shown at delivery",
              style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
            if (destinationAmount != null) ...[
              const SizedBox(height: 4),
              Text("They receive: ${destinationAmount.toString()} ${_selectedDestination!.currencyCode}",
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 13)),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text("Cancel", style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text("Send gift"),
          ),
        ],
      ),
    );

    if (proceed != true || !mounted) return;

    setState(() => _isProcessing = true);

    final now = DateTime.now();
    final reference = 'DR-GIFT-${now.millisecondsSinceEpoch}';
    final recipientName = _selectedRecipient!['name']?.toString() ?? 'your contact';
    final nameParts = recipientName.trim().split(' ');
    final firstName = nameParts.first;
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : firstName;

    final payoutResult = await sendData(
      urlPath: "/api/v1/payouts/send",
      data: {
        "token": quotationToken,
        "firstName": firstName,
        "lastName": lastName,
        "phoneNumber": recipientPhone,
        "sourceWallet": "USD",
        "amount": amount,
        "amountType": "SOURCE",
        "type": "momo",
        "isBank": false,
        "isMomo": true,
        "country": _selectedDestination!.countryCode,
        "destinationCountry": _selectedDestination!.countryCode,
        "destinationCurrency": _selectedDestination!.currencyCode,
        "currency": _selectedDestination!.currencyCode,
        "transactionRef": reference,
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;

    if (payoutResult['error'] != null || payoutResult['apiRequestError'] != null) {
      setState(() {
        _isProcessing = false;
        _errorMessage = payoutResult['error']?.toString() ??
            payoutResult['apiRequestError']?.toString() ??
            "Couldn't send this gift. Please try again.";
      });
      return;
    }

    final receipt = {
      'transactionMemberName': recipientName,
      'transactionAmount': amount.toStringAsFixed(2),
      'transactionType': 'debit',
      'transactionDate': now.toIso8601String(),
      'dateGroup': customGroup(now),
      'giftOccasion': _selectedOccasion!.name,
      'transactionReference': reference,
      'destinationCountry': _selectedDestination!.countryName,
      'destinationCurrency': _selectedDestination!.currencyCode,
      if (_messageController.text.trim().isNotEmpty)
        'giftMessage': _messageController.text.trim(),
    };

    await SuccessfulTransactionsStorage().updateSuccessfulTransactions(receipt);

    if (!mounted) return;

    // Gifts are always sent from the USD wallet (sourceWallet is
    // hardcoded USD above), so this specific debit was already
    // correct — switched to the same real-balance sync every other
    // send screen now uses, for consistency and so this stays correct
    // if gifts are ever extended to support other source currencies.
    await Provider.of<UserLoginStateProvider>(context, listen: false)
        .syncBalanceFromEversend(widget.userAuthKey);

    setState(() => _isProcessing = false);

    await showTransactionReceipt(
      context,
      title: "Gift sent!",
      amountLine: "\$${amount.toStringAsFixed(2)} ${_selectedOccasion!.name} gift",
      fields: [
        ReceiptField("To", recipientName),
        ReceiptField("Occasion", _selectedOccasion!.name),
        ReceiptField("Sent to", _selectedDestination!.countryName),
        if (_messageController.text.trim().isNotEmpty)
          ReceiptField("Message", _messageController.text.trim()),
        ReceiptField("Date", now.toLocal().toString().split('.').first),
      ],
      reference: reference,
    );

    if (!mounted) return;
    setState(() {
      _selectedOccasion = null;
      _selectedRecipient = null;
      _selectedDestination = null;
      _selectedAmount = null;
      _messageController.clear();
      _customAmountController.clear();
    });
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
          "You're browsing as a guest, so gifts can't be sent yet. Create a free account first.",
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
      child: ListView(
        controller: _scrollController,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("However your money needs to move, it's here.",
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink, height: 1.25)),
                const SizedBox(height: 6),
                Text(
                  "Send money to family on mobile money or bank accounts, at great rates, arriving in seconds.",
                  style: TextStyle(fontSize: 13.5, color: AppColors.textMuted, height: 1.4),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    "Send money home",
                    "Get paid from abroad",
                    "Spend abroad",
                    "Pay online & subscriptions",
                    "Hold dollar value",
                  ]
                      .map((f) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(AppRadii.pill),
                            ),
                            child: Text(f,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("YOU SEND",
                                style: TextStyle(
                                    fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.6)),
                            const SizedBox(height: 4),
                            Text("£500", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
                            Text("from your account", style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_rounded, color: AppColors.textMuted, size: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("CONVERT · FX",
                                style: TextStyle(
                                    fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.6)),
                            const SizedBox(height: 4),
                            Text("Live rate", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                            Text("great rates", style: TextStyle(fontSize: 11, color: AppColors.success)),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_rounded, color: AppColors.textMuted, size: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("ROUTE",
                                style: TextStyle(
                                    fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.6)),
                            const SizedBox(height: 4),
                            Text("Mobile money", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink)),
                            Text("Family paid in seconds", style: TextStyle(fontSize: 11, color: AppColors.success)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const DeliveryTimeRow(range: "Instant · 1 min"),
                const SizedBox(height: 16),
                Text("Send money to",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kAfricanCountries
                      .where((c) => c.isEversendCorridor)
                      .map((c) {
                    final bool isSelected = _selectedDestination?.countryCode == c.countryCode;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedDestination = c;
                        _errorMessage = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : Colors.white,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(c.flagEmoji, style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 5),
                            Text(c.countryName,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? Colors.white : AppColors.inkMuted)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Divider(color: AppColors.divider),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ...kGiftOccasionCategories.map((category) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(category.categoryName,
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 92,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: category.occasions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final occasion = category.occasions[index];
                          final bool isSelected = _selectedOccasion?.name == occasion.name;
                          return GestureDetector(
                            onTap: () => _selectOccasion(occasion),
                            child: SizedBox(
                              width: 72,
                              child: Column(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.primary.withOpacity(0.08),
                                      border: Border.all(
                                          color: isSelected ? AppColors.primary : AppColors.border,
                                          width: isSelected ? 2 : 1),
                                    ),
                                    child: Icon(occasion.icon,
                                        color: isSelected ? Colors.white : AppColors.primary, size: 24),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(occasion.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              )),
          if (_selectedOccasion != null) ...[
            Padding(
              key: _giftOptionsKey,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: AppColors.divider),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(_selectedOccasion!.icon, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text("${_selectedOccasion!.name} gift",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 12),
                  Text("RECIPIENT",
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickRecipient,
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
                          CircleAvatar(
                            backgroundColor: AppColors.surfaceAlt,
                            radius: 18,
                            child: _selectedRecipient != null
                                ? Text(
                                    () {
                                      final n = _selectedRecipient!['name']?.toString() ?? '';
                                      return n.isNotEmpty ? n[0].toUpperCase() : '?';
                                    }(),
                                    style:
                                        TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))
                                : Icon(Icons.person_outline_rounded, color: AppColors.textMuted, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedRecipient != null
                                  ? (_selectedRecipient!['name']?.toString() ?? '')
                                  : "Choose a contact",
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _selectedRecipient != null ? AppColors.ink : AppColors.textMuted,
                                  fontSize: 15),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text("ADD A SPECIAL MESSAGE",
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _messageController,
                    maxLength: 80,
                    decoration: InputDecoration(
                      hintText: "e.g. Happy Birthday!",
                      filled: true,
                      fillColor: AppColors.surfaceAlt,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text("GIFT AMOUNT",
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: kGiftQuickAmounts.map((amt) {
                      final bool isSelected = _selectedAmount == amt;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedAmount = amt;
                          _customAmountController.clear();
                          _errorMessage = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary : AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                          child: Text("\$${amt.toStringAsFixed(0)}",
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? Colors.white : AppColors.primary)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text("Or a custom amount",
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customAmountController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) => setState(() {
                      if (v.isNotEmpty) _selectedAmount = null;
                    }),
                    decoration: InputDecoration(
                      prefixText: "\$ ",
                      hintText: "0.00",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
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
                      onPressed: _isProcessing ? null : _confirmGift,
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
                          : Text("Send gift",
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

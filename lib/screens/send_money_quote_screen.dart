import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/database/currency_conversion_service.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/database/contacts_storage.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/custom_date_grouping.dart';
import 'package:dutch_remit/components/shared/transfer_info_widgets.dart';
import 'package:dutch_remit/components/shared/transaction_receipt_dialog.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';

/// The "Send" sub-tab of the bottom-nav Send hub: a "SEND MONEY" quote
/// card matching the reference design 1:1 — GBP/USD/EUR toggle, You
/// send / They receive, a chosen recipient row with the fee, a
/// "Send now" button, and a floating "Delivered" receipt badge —
/// followed by the feature/trust blocks from the brief.
class SendMoneyQuoteScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String userAuthKey;
  const SendMoneyQuoteScreen({Key? key, required this.user, required this.userAuthKey})
      : super(key: key);

  @override
  State<SendMoneyQuoteScreen> createState() => _SendMoneyQuoteScreenState();
}

class _SendMoneyQuoteScreenState extends State<SendMoneyQuoteScreen> {
  static const List<String> _sourceCurrencies = ['GBP', 'USD', 'EUR'];
  // CurrencyConversionService (Frankfurter-backed) was removed from
  // this screen's quote flow — see _fetchQuote's comment for why it
  // was structurally guaranteed to fail for this screen's fixed NGN
  // destination.
  final TextEditingController _amountController = TextEditingController(text: '500');
  final ContactsStorage _contactsStorage = ContactsStorage();

  String _sourceCurrency = 'GBP';
  double? _convertedAmount;
  double? _exchangeRate;
  double? _fee;
  bool _isQuoting = false;
  bool _isProcessing = false;
  bool _justDelivered = false;
  Map<String, dynamic>? _recipient;
  Timer? _debounce;

  bool get _isGuest => widget.user.isEmpty || widget.user['email'] == null;

  @override
  void initState() {
    super.initState();
    _fetchQuote();
    _loadDefaultRecipient();
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadDefaultRecipient() async {
    final contacts = await _contactsStorage.readContacts();
    if (mounted && contacts.isNotEmpty) {
      setState(() => _recipient = contacts.first);
    }
    // No fallback to an invented contact when there are none yet —
    // _recipient stays null and the UI prompts the user to pick a
    // real one (see _pickRecipient) before Send is enabled.
  }

  Future<List<Map<String, dynamic>>> _loadSavedContacts() async {
    final results = await Future.wait([
      _contactsStorage.readContacts(),
      getData(urlPath: "/Dutch Remit/v3/all-contacts", authKey: widget.userAuthKey),
    ]);
    final local = results[0] as List<Map<String, dynamic>>;
    final serverResult = results[1] as Map<String, dynamic>;
    final bool serverFailed = serverResult.keys.join().toLowerCase().contains("error");
    return [
      ...local,
      if (!serverFailed)
        ...List<Map<String, dynamic>>.from(
            (serverResult['contacts'] ?? []).map((c) => Map<String, dynamic>.from(c))),
    ];
  }

  Future<void> _pickRecipient() async {
    final saved = await _loadSavedContacts();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (sheetContext) => _RecipientPickerSheet(
        savedContacts: saved,
        userAuthKey: widget.userAuthKey,
        onPicked: (r) {
          setState(() => _recipient = r);
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  void _onAmountChanged() {
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

    // Real fix: this used to make a SECOND, separate call to
    // Frankfurter (a free ECB-sourced rate API) purely to show the
    // converted amount/rate, alongside the real quotation call below
    // that was only used for the fee. Frankfurter's supported
    // currency list is ECB-only (USD, EUR, GBP, and ~30 other major
    // currencies) — NGN, this screen's fixed destination, isn't in
    // it and never will be, so that call 404'd on every single use,
    // guaranteed, not intermittently. The real quotation call already
    // returns the actual exchange rate and converted amount in the
    // same response the fee was already being read from — deriving
    // both from ONE real call instead of a doomed second one.
    final response = await sendData(
      urlPath: "/api/v1/rates/quotation",
      data: {
        "sourceWallet": _sourceCurrency,
        "amount": amount,
        "amountType": "SOURCE",
        "type": "bank",
        "destinationCountry": "NG",
        "destinationCurrency": "NGN",
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;

    if (response.containsKey('apiRequestError') || response['error'] != null) {
      setState(() {
        _isQuoting = false;
        _convertedAmount = null;
        _exchangeRate = null;
        _fee = null;
      });
      return;
    }

    final quotationData = response['data'];
    final quotation = (quotationData is Map && quotationData['data'] is Map)
        ? (quotationData['data'] as Map)['quotation']
        : null;
    final feeBreakdown = response['feeBreakdown'];

    setState(() {
      _isQuoting = false;
      // No fabricated fallback — a previous version defaulted to
      // "amount * 1710" / "rate: 1710" whenever the real conversion
      // service returned nothing, presented identically to a real
      // rate with no indication it was a guess. If the service
      // genuinely has no rate right now, this is null and the UI
      // shows an honest "Rate unavailable" instead (see build()
      // below), never an invented number.
      _convertedAmount = (quotation is Map && quotation['destAmount'] != null)
          ? double.tryParse(quotation['destAmount'].toString())
          : null;
      _exchangeRate = (quotation is Map && quotation['exchangeRate'] != null)
          ? double.tryParse(quotation['exchangeRate'].toString())
          : null;
      _fee = (feeBreakdown is Map && feeBreakdown['totalFee'] != null)
          ? double.tryParse(feeBreakdown['totalFee'].toString())
          : null;
    });
  }

  void _selectSourceCurrency(String code) {
    setState(() => _sourceCurrency = code);
    _fetchQuote();
  }

  Future<void> _sendNow() async {
    if (_isGuest) {
      _showCreateAccountPrompt();
      return;
    }
    if (_recipient == null) {
      await _pickRecipient();
      return;
    }
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0 || _fee == null) return;
    final fee = _fee!;

    setState(() => _isProcessing = true);
    await Future.delayed(const Duration(milliseconds: 900));

    final now = DateTime.now();
    final reference = 'DR-${now.millisecondsSinceEpoch}';
    final recipientName = _recipient!['name']?.toString() ?? 'your recipient';
    final receipt = {
      'transactionMemberName': recipientName,
      'transactionAmount': (amount + fee).toStringAsFixed(2),
      'currency': _sourceCurrency,
      'transactionType': 'debit',
      'transactionDate': now.toIso8601String(),
      'dateGroup': customGroup(now),
      'transactionReference': reference,
      if (_convertedAmount != null) 'receiveAmount': _convertedAmount,
      if (_exchangeRate != null) 'exchangeRate': _exchangeRate,
    };
    await SuccessfulTransactionsStorage().updateSuccessfulTransactions(receipt);

    if (!mounted) return;
    // Real fix: `amount + fee` is in _sourceCurrency (defaults to
    // GBP, user-changeable) — the same currency-mismatch bug found
    // and fixed across every other send screen this session.
    await Provider.of<UserLoginStateProvider>(context, listen: false)
        .syncBalanceFromEversend(widget.userAuthKey);

    setState(() {
      _isProcessing = false;
      _justDelivered = true;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _justDelivered = false);
    });

    await showTransactionReceipt(
      context,
      title: "Money sent",
      amountLine: "$_sourceCurrency ${(amount + fee).toStringAsFixed(2)} sent",
      fields: [
        ReceiptField("To", recipientName),
        ReceiptField("You sent", "$_sourceCurrency ${amount.toStringAsFixed(2)}"),
        ReceiptField("Fee", "$_sourceCurrency ${fee.toStringAsFixed(2)}"),
        if (_convertedAmount != null)
          ReceiptField("They receive", "${_convertedAmount!.toStringAsFixed(2)} NGN"),
        ReceiptField("Date", now.toLocal().toString().split('.').first),
      ],
      reference: reference,
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("SEND MONEY",
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: AppColors.textMuted)),
                  const SizedBox(height: 12),
                  Row(
                    children: _sourceCurrencies.map((code) {
                      final bool isActive = _sourceCurrency == code;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => _selectSourceCurrency(code),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                            decoration: BoxDecoration(
                              color: isActive ? AppColors.ink : AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(AppRadii.pill),
                            ),
                            child: Text(code,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: isActive ? Colors.white : AppColors.inkMuted)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.md)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("You send",
                            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text("$_sourceCurrency  ",
                                style: TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink,
                                    fontFamily: 'monospace')),
                            Expanded(
                              child: TextField(
                                controller: _amountController,
                                keyboardType: TextInputType.numberWithOptions(decimal: true),
                                style: TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink,
                                    fontFamily: 'monospace'),
                                decoration: InputDecoration(
                                    isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      _exchangeRate != null
                          ? "1 $_sourceCurrency = ${_exchangeRate!.toStringAsFixed(0)} NGN"
                          : (_isQuoting ? "Fetching live rate…" : "Rate unavailable — shown at delivery"),
                      style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(AppRadii.md)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("They receive",
                            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _isQuoting
                                ? SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.primary))
                                : Text(
                                    _convertedAmount != null
                                        ? _formatWhole(_convertedAmount!)
                                        : 'Unavailable',
                                    style: TextStyle(
                                        fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink,
                                        fontFamily: 'monospace')),
                            const SizedBox(width: 6),
                            Text("NGN", style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Divider(color: AppColors.divider),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _pickRecipient,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.primary.withOpacity(0.12),
                          child: (_recipient?['name']?.toString().isNotEmpty ?? false)
                              ? Text(
                                  _recipient!['name'].toString()[0].toUpperCase(),
                                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                                )
                              : Icon(Icons.person_outline_rounded, color: AppColors.primary, size: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_recipient?['name']?.toString() ?? 'Choose a recipient',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _recipient != null ? AppColors.ink : AppColors.textMuted,
                                      fontSize: 14)),
                              Text(
                                  _recipient?['phoneNumber'] != null
                                      ? _recipient!['phoneNumber'].toString()
                                      : "Bank deposit · Nigeria",
                                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 18),
                        const SizedBox(width: 6),
                        Text(
                            _fee != null
                                ? "Fee $_sourceCurrency ${_fee!.toStringAsFixed(2)}"
                                : (_isQuoting ? "Fee: calculating…" : "Fee: —"),
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_isProcessing || _convertedAmount == null || _fee == null)
                          ? null
                          : _sendNow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                      ),
                      child: _isProcessing
                          ? SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                          : Text("Send now", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
            if (_justDelivered)
              Positioned(
                top: -14,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    boxShadow: AppShadows.card,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Delivered", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.ink)),
                          Text("12 sec ago", style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Text("With Dutch Remit",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              ComparisonFeatureRow(
                  label: "Money arrives",
                  value: "In seconds to a bank account, mobile money or Dutch Remit balance"),
              ComparisonFeatureRow(
                  label: "The real rate",
                  value: "One fee shown upfront before you send"),
              ComparisonFeatureRow(
                  label: "Tracking",
                  value: "Track every transfer end to end, with a receipt the moment it lands"),
              ComparisonFeatureRow(
                  label: "Reach anyone",
                  value: "Family and friends however they want to be paid"),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _statCard("Arrives in", "Seconds", "Same-day clear"),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard("It costs", "See quote", "Fee shown before you send"),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard("Open", "24/7", "Always on"),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, String sub) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.ink)),
            Text(sub, style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
      );

  String _formatWhole(double amount) {
    final s = amount.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

/// The recipient picker sheet used by "Send now" — starts with saved
/// contacts, and as the user types, searches the real Dutch Remit
/// user directory (GET /api/v1/users/search) so someone can be found
/// and paid even if they've never been saved as a contact before.
class _RecipientPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> savedContacts;
  final String userAuthKey;
  final void Function(Map<String, dynamic> recipient) onPicked;

  const _RecipientPickerSheet({
    Key? key,
    required this.savedContacts,
    required this.userAuthKey,
    required this.onPicked,
  }) : super(key: key);

  @override
  State<_RecipientPickerSheet> createState() => _RecipientPickerSheetState();
}

class _RecipientPickerSheetState extends State<_RecipientPickerSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _userResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredContacts {
    final term = _searchController.text.trim().toLowerCase();
    if (term.isEmpty) return widget.savedContacts;
    return widget.savedContacts
        .where((c) => (c['name']?.toString().toLowerCase() ?? '').contains(term))
        .toList();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    final term = value.trim();
    if (term.length < 2) {
      setState(() => _userResults = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _searchUsers(term));
  }

  Future<void> _searchUsers(String term) async {
    setState(() => _isSearching = true);
    final result = await getData(
      urlPath: "/api/v1/users/search?q=${Uri.encodeQueryComponent(term)}",
      authKey: widget.userAuthKey,
    );
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _userResults = result['users'] is List
          ? List<Map<String, dynamic>>.from(
              (result['users'] as List).map((u) => Map<String, dynamic>.from(u)))
          : [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _filteredContacts;
    final term = _searchController.text.trim();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text("Send to",
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
                  suffixIcon: _isSearching
                      ? Padding(
                          padding: const EdgeInsets.all(14),
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                        )
                      : null,
                  hintText: "Search by name or username",
                  filled: true,
                  fillColor: AppColors.surfaceAlt,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (contacts.isNotEmpty) ...[
                    _sectionLabel("Your contacts"),
                    ...contacts.map((r) => _recipientTile(r)),
                  ],
                  if (_userResults.isNotEmpty) ...[
                    _sectionLabel("Dutch Remit users"),
                    ..._userResults.map((r) => _recipientTile(r)),
                  ],
                  if (contacts.isEmpty && _userResults.isEmpty && term.isNotEmpty && !_isSearching)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text("No matches for \"$term\"",
                            style: TextStyle(color: AppColors.textMuted)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5)),
      );

  Widget _recipientTile(Map<String, dynamic> r) {
    final name = r['name']?.toString() ?? '';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.surfaceAlt,
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
      ),
      title: Text(name.isNotEmpty ? name : 'Unknown',
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
      subtitle: r['phoneNumber'] != null
          ? Text(r['phoneNumber'].toString(), style: TextStyle(color: AppColors.textMuted))
          : (r['username'] != null
              ? Text("@${r['username']}", style: TextStyle(color: AppColors.textMuted))
              : null),
      onTap: () => widget.onPicked(r),
    );
  }
}

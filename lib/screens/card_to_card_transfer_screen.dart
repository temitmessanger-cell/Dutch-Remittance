import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/components/shared/transaction_receipt_dialog.dart';

/// Move money from one of your own cards to another, or to another
/// Dutch Remit user's card — real backend ledger, no local/simulated
/// data. See Backend/src/routes/cards.js: GET /mine, POST /transfer.
class CardToCardTransferScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  const CardToCardTransferScreen({Key? key, required this.user, this.userAuthKey}) : super(key: key);

  @override
  State<CardToCardTransferScreen> createState() => _CardToCardTransferScreenState();
}

class _CardToCardTransferScreenState extends State<CardToCardTransferScreen> {
  final TextEditingController _amountController = TextEditingController(text: '50');
  List<Map<String, dynamic>> _cards = [];
  Map<String, dynamic>? _fromCard;
  Map<String, dynamic>? _toCard;
  Map<String, dynamic>? _toUser; // set only when sending to another user
  bool _isSending = false;
  bool _isDone = false;
  bool _isLoading = true;
  bool _toAnotherUser = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    final result = await getData(urlPath: "/api/v1/cards/mine", authKey: widget.userAuthKey);
    final cards = result['cards'] is List
        ? List<Map<String, dynamic>>.from((result['cards'] as List).map((c) => Map<String, dynamic>.from(c)))
        : <Map<String, dynamic>>[];
    if (mounted) {
      setState(() {
        _cards = cards;
        _fromCard = cards.isNotEmpty ? cards.first : null;
        _toCard = cards.length > 1 ? cards[1] : null;
        _isLoading = false;
      });
    }
  }

  String _maskedNumber(Map<String, dynamic>? card) {
    if (card == null) return 'No card';
    return card['label']?.toString() ?? 'Card';
  }

  Future<void> _pickRecipientUser() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (sheetContext) => _UserSearchSheet(userAuthKey: widget.userAuthKey),
    );
    if (result != null) {
      setState(() {
        _toUser = result;
        _toCard = null;
      });
    }
  }

  Future<void> _sendTransfer() async {
    if (_fromCard == null) return;
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = "Enter a valid amount.");
      return;
    }
    if (_toAnotherUser) {
      if (_toUser == null) {
        setState(() => _errorMessage = "Choose who you're sending to.");
        return;
      }
    } else {
      if (_toCard == null) {
        setState(() => _errorMessage = "Choose a destination card.");
        return;
      }
      if (_fromCard!['id'] == _toCard!['id']) {
        setState(() => _errorMessage = "Choose two different cards to transfer between.");
        return;
      }
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    final result = await sendData(
      urlPath: "/api/v1/cards/transfer",
      data: {
        "fromCardId": _fromCard!['id'],
        "fromCardSource": _fromCard!['source'],
        if (_toAnotherUser) "toUserId": _toUser!['id'],
        if (!_toAnotherUser) "toCardId": _toCard!['id'],
        if (!_toAnotherUser) "toCardSource": _toCard!['source'],
        "amount": amount,
        "currency": "USD",
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

    // Always USD (currency is hardcoded "USD" in the request above),
    // so this specific debit was already correct — switched to the
    // real-balance sync for consistency with every other send screen.
    await Provider.of<UserLoginStateProvider>(context, listen: false)
        .syncBalanceFromEversend(widget.userAuthKey);

    setState(() {
      _isSending = false;
      _isDone = true;
    });

    final reference = result['transfer']?['reference']?.toString() ??
        'DR-CT-${DateTime.now().millisecondsSinceEpoch}';
    await showTransactionReceipt(
      context,
      title: "Transfer complete",
      amountLine: "\$${amount.toStringAsFixed(2)} moved",
      fields: [
        ReceiptField("From", _maskedNumber(_fromCard)),
        ReceiptField(
            "To", _toAnotherUser ? (_toUser!['name']?.toString() ?? 'Another user') : _maskedNumber(_toCard)),
      ],
      reference: reference,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Card to Card transfer",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 17)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _isDone
                ? _buildSuccess()
                : _cards.isEmpty
                    ? _buildNoCards()
                    : _buildForm(),
      ),
    );
  }

  Widget _buildNoCards() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.credit_card_off_outlined, size: 44, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text("You need a card first",
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16)),
          const SizedBox(height: 6),
          Text("Create or link a card before you can send a card-to-card transfer.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            Expanded(child: _modeTab("My own cards", !_toAnotherUser)),
            const SizedBox(width: 8),
            Expanded(child: _modeTab("Another user", _toAnotherUser)),
          ],
        ),
        const SizedBox(height: 20),
        Text("From", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        _cardPicker(_fromCard, (card) => setState(() => _fromCard = card)),
        const SizedBox(height: 8),
        if (!_toAnotherUser)
          Center(
            child: IconButton(
              onPressed: (_fromCard == null || _toCard == null)
                  ? null
                  : () => setState(() {
                        final tmp = _fromCard;
                        _fromCard = _toCard;
                        _toCard = tmp;
                      }),
              icon: Icon(Icons.swap_vert_rounded, color: AppColors.primary),
            ),
          ),
        Text("To", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        if (_toAnotherUser)
          InkWell(
            onTap: _pickRecipientUser,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_search_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _toUser != null ? (_toUser!['name']?.toString() ?? 'Selected user') : "Choose a Dutch Remit user",
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _toUser != null ? AppColors.ink : AppColors.textMuted),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
                ],
              ),
            ),
          )
        else
          _cardPicker(_toCard, (card) => setState(() => _toCard = card)),
        const SizedBox(height: 20),
        Text("Amount", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Text("\$ ", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink),
                  decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSending ? null : _sendTransfer,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: _isSending
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : Text("Transfer", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _modeTab(String label, bool isActive) => GestureDetector(
        onTap: () => setState(() {
          _toAnotherUser = label == "Another user";
          _errorMessage = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: isActive ? Colors.white : AppColors.inkMuted)),
        ),
      );

  Widget _cardPicker(Map<String, dynamic>? selected, void Function(Map<String, dynamic>) onSelect) {
    return GestureDetector(
      onTap: () async {
        final picked = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _cards
                  .map((c) => ListTile(
                        leading: Icon(Icons.credit_card_rounded, color: AppColors.primary),
                        title: Text(_maskedNumber(c)),
                        onTap: () => Navigator.of(sheetContext).pop(c),
                      ))
                  .toList(),
            ),
          ),
        );
        if (picked != null) onSelect(picked);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.credit_card_rounded, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text(_maskedNumber(selected),
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink))),
            Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56),
          const SizedBox(height: 16),
          Text("Transfer complete",
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 8),
          Text("\$${_amountController.text} moved from ${_maskedNumber(_fromCard)} to ${_maskedNumber(_toCard)}.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
              ),
              child: Text("Done", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Search sheet for picking another real Dutch Remit user to send a
/// card transfer to — GET /api/v1/users/search, same directory the
/// Send flow's recipient picker uses.
class _UserSearchSheet extends StatefulWidget {
  final String? userAuthKey;
  const _UserSearchSheet({Key? key, this.userAuthKey}) : super(key: key);

  @override
  State<_UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<_UserSearchSheet> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final term = value.trim();
    if (term.length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(term));
  }

  Future<void> _search(String term) async {
    setState(() => _isSearching = true);
    final result = await getData(
      urlPath: "/api/v1/users/search?q=${Uri.encodeQueryComponent(term)}",
      authKey: widget.userAuthKey,
    );
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _results = result['users'] is List
          ? List<Map<String, dynamic>>.from((result['users'] as List).map((u) => Map<String, dynamic>.from(u)))
          : [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text("Send to a Dutch Remit user",
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
                  suffixIcon: _isSearching
                      ? Padding(
                          padding: const EdgeInsets.all(14),
                          child: SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
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
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final r = _results[index];
                  final name = r['name']?.toString() ?? '';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.surfaceAlt,
                      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ),
                    title: Text(name.isNotEmpty ? name : 'Unknown',
                        style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                    subtitle: r['username'] != null
                        ? Text("@${r['username']}", style: TextStyle(color: AppColors.textMuted))
                        : null,
                    onTap: () => Navigator.of(context).pop(r),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

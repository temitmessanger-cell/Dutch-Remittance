import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';

/// Bank accounts (Klasha-backed) for cross-border transfers, in NGN
/// and GHS — required once per currency before a Klasha-routed
/// corridor (one our main provider doesn't cover) can send: funds
/// move from the user's Eversend wallet into this bank account first,
/// then the real payout goes out from there. See
/// Backend/src/routes/klasha.js and paymentRouter.js's
/// VIRTUAL_ACCOUNT_CURRENCIES two-hop flow.
///
/// Deliberately called "Bank account" everywhere in this screen's
/// user-facing copy, never "virtual account" or "VAS" — those are
/// internal/provider terms a user has no reason to know.
class VirtualAccountsScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  const VirtualAccountsScreen({Key? key, required this.user, this.userAuthKey}) : super(key: key);

  @override
  State<VirtualAccountsScreen> createState() => _VirtualAccountsScreenState();
}

class _VirtualAccountsScreenState extends State<VirtualAccountsScreen> {
  static const List<Map<String, String>> _currencies = [
    {'code': 'NGN', 'country': 'Nigeria', 'flag': '🇳🇬'},
    {'code': 'GHS', 'country': 'Ghana', 'flag': '🇬🇭'},
  ];

  List<Map<String, dynamic>> _accounts = [];
  bool _isLoading = true;
  bool _isCreating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final result = await getData(urlPath: "/api/v1/klasha/virtual-accounts/mine", authKey: widget.userAuthKey);
    if (!mounted) return;
    setState(() {
      _accounts = result['virtualAccounts'] is List
          ? List<Map<String, dynamic>>.from(
              (result['virtualAccounts'] as List).map((a) => Map<String, dynamic>.from(a)))
          : [];
      _isLoading = false;
    });
  }

  bool get _isGuest => widget.user.isEmpty || widget.user['email'] == null;

  double get _nextFee => _accounts.isEmpty ? 0.5 : 1.5;

  /// Collects the fields Klasha's virtual-account creation actually
  /// needs, pre-filled from the signed-in user's profile where
  /// available but always editable — the previous version silently
  /// sent whatever was in `widget.user` with no form and no chance to
  /// fix a missing or wrong name before the request went out.
  Future<Map<String, String>?> _collectAccountDetails(String currency) async {
    final firstNameController = TextEditingController(
        text: widget.user['first_name']?.toString() ?? '');
    final lastNameController = TextEditingController(
        text: widget.user['last_name']?.toString() ?? '');
    final emailController =
        TextEditingController(text: widget.user['email']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Confirm your details",
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.ink)),
                  const SizedBox(height: 4),
                  Text(
                      "This is the name Klasha will register on your $currency bank account. It must match your ID.",
                      style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4)),
                  const SizedBox(height: 18),
                  _formField("First name", firstNameController),
                  const SizedBox(height: 12),
                  _formField("Last name", lastNameController),
                  const SizedBox(height: 12),
                  _formField("Email", emailController,
                      keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (formKey.currentState?.validate() != true) return;
                        Navigator.of(sheetContext).pop({
                          'firstName': firstNameController.text.trim(),
                          'lastName': lastNameController.text.trim(),
                          'email': emailController.text.trim(),
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.md)),
                      ),
                      child: Text("Continue",
                          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    return result;
  }

  Widget _formField(String label, TextEditingController controller,
      {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 14.5, color: AppColors.ink),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? '$label is required' : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceAlt,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadii.md)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary, width: 1.6),
                borderRadius: BorderRadius.circular(AppRadii.md)),
            errorBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.danger),
                borderRadius: BorderRadius.circular(AppRadii.md)),
            border: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadii.md)),
          ),
        ),
      ],
    );
  }

  Future<void> _createAccount(String currency) async {
    if (_isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Create an account to set up a bank account.")),
      );
      return;
    }

    final details = await _collectAccountDetails(currency);
    if (details == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text("Create $currency bank account",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        content: Text(
          "A one-time \$${_nextFee.toStringAsFixed(2)} fee applies. This account is created once and reused for every future transfer through this corridor.",
          style: TextStyle(color: AppColors.inkMuted, height: 1.4),
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
            child: Text("Create — \$${_nextFee.toStringAsFixed(2)}"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    final result = await sendData(
      urlPath: "/api/v1/klasha/virtual-account",
      data: {
        "currency": currency,
        "email": details['email'],
        "firstName": details['firstName'],
        "lastName": details['lastName'],
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (result.containsKey('apiRequestError') || result['error'] != null) {
      setState(() {
        _errorMessage = result['error']?.toString() ?? result['apiRequestError'].toString();
      });
      return;
    }

    await _loadAccounts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Bank Accounts",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 17)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppColors.primary))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Text("Local bank accounts for cross-border transfers",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  const SizedBox(height: 8),
                  Text(
                    "For corridors our main provider doesn't cover, we route funds through your own local bank account first, then complete the transfer — a one-time setup per currency.",
                    style: TextStyle(fontSize: 13.5, color: AppColors.textMuted, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
                    ),
                    const SizedBox(height: 14),
                  ],
                  ..._currencies.map((c) => _buildCurrencyCard(c)),
                ],
              ),
      ),
    );
  }

  Widget _buildCurrencyCard(Map<String, String> currencyInfo) {
    final code = currencyInfo['code']!;
    final existing = _accounts.where((a) => a['currency'] == code).toList();
    final account = existing.isNotEmpty ? existing.first : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
            children: [
              Text(currencyInfo['flag']!, style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${currencyInfo['country']} ($code)",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    Text(account != null ? "Active" : "Not set up yet",
                        style: TextStyle(
                            fontSize: 12,
                            color: account != null ? AppColors.success : AppColors.textMuted,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (account == null)
                ElevatedButton(
                  onPressed: _isCreating ? null : () => _createAccount(code),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
                  ),
                  child: _isCreating
                      ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text("Create", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
            ],
          ),
          if (account != null) ...[
            const SizedBox(height: 12),
            Divider(color: AppColors.divider),
            const SizedBox(height: 8),
            _accountRow("Account number", account['account_number']?.toString() ?? '—'),
            _accountRow("Bank", account['bank_name']?.toString() ?? '—'),
            _accountRow("Account name", account['account_name']?.toString() ?? '—'),
          ],
        ],
      ),
    );
  }

  Widget _accountRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            Flexible(
              child: InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text("Copied"), backgroundColor: AppColors.success));
                },
                child: Text(value,
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
              ),
            ),
          ],
        ),
      );
}

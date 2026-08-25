import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';

/// Klasha NGN/GHS virtual accounts — required once per currency
/// before a Klasha-routed corridor (one Eversend doesn't cover) can
/// send: funds move from the user's Eversend wallet into this account
/// first, then the real payout goes out from there. See
/// Backend/src/routes/klasha.js and paymentRouter.js's
/// VIRTUAL_ACCOUNT_CURRENCIES two-hop flow.
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

  Future<void> _createAccount(String currency) async {
    if (_isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Create an account to set up a virtual account.")),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text("Create $currency virtual account",
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
    if (confirmed != true) return;

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    final result = await sendData(
      urlPath: "/api/v1/klasha/virtual-account",
      data: {
        "currency": currency,
        "email": widget.user['email'],
        "firstName": widget.user['first_name'],
        "lastName": widget.user['last_name'],
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
        title: Text("Virtual Accounts",
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
                    "For corridors our main provider doesn't cover, we route funds through your own local virtual account first, then complete the transfer — a one-time setup per currency.",
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/african_country_data.dart';
import 'package:dutch_remit/utilities/custom_date_grouping.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/components/shared/transaction_receipt_dialog.dart';

/// The real withdrawal flow for Mobile Money / Orange Money: pick the
/// destination country, enter the recipient phone number, quote and
/// confirm — calling the backend's unified quotation + send endpoints
/// (POST /api/v1/rates/quotation, POST /api/v1/payouts/send), which
/// automatically route to Eversend or Klasha depending on the
/// destination currency. No fake instant debit.
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
  final TextEditingController _nameController = TextEditingController();

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
        "amountType": "SOURCE",
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

  Future<void> _confirmWithdrawal() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || !phone.startsWith('+')) {
      setState(() => _errorMessage = "Enter the phone number in international format, e.g. +256712345678.");
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = "Enter the recipient's full name.");
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
        "firstName": firstName,
        "lastName": lastName,
        "country": _country.countryCode,
        "phoneNumber": phone,
        "isBank": false,
        "isMomo": true,
        "amount": widget.amount,
        "currency": _country.currencyCode,
        "destinationCurrency": _country.currencyCode,
        "destinationCountry": _country.countryCode,
        "quotationToken": _quote?['data']?['quotationToken'],
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
    await SuccessfulTransactionsStorage().updateSuccessfulTransactions({
      'transactionMemberName': "Withdrawal · ${_nameController.text.trim()} (${_country.countryName})",
      'transactionAmount': widget.amount.toStringAsFixed(2),
      'transactionType': 'debit',
      'transactionDate': now.toIso8601String(),
      'dateGroup': customGroup(now),
      'withdrawalMethod': 'mobile_money',
      'withdrawalSpeed': widget.withdrawalSpeed,
      'eversendReference': transactionRef,
      'paymentProvider': result['provider'],
    });

    if (!mounted) return;
    Provider.of<UserLoginStateProvider>(context, listen: false)
        .updateBankBalance('debit', widget.amount.toStringAsFixed(2));

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
        child: _isDone ? _buildSuccess() : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text("Withdrawing \$${widget.amount.toStringAsFixed(2)}",
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
                    child: Text("via Klasha",
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
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: _fieldDecoration("+256712345678"),
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
            "\$${widget.amount.toStringAsFixed(2)} is on its way to ${_nameController.text.trim()} in ${_country.countryName}.",
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

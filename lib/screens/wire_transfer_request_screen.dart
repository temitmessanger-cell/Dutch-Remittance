import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';

/// A wire transfer request screen for KlashaWire — Klasha's B2B wire
/// product for paying overseas suppliers, distinct from the instant
/// mobile money/bank payouts elsewhere in the app. Genuinely
/// different in kind, not just size: $500 minimum, $50,000 maximum,
/// 1–4 business days to settle, and — because the exact Klasha API
/// endpoint for this product isn't publicly documented (see
/// Backend/src/routes/klasha.js's POST /wire) — submitted as a
/// request for manual processing rather than an instant automated
/// transfer. The screen is upfront about that distinction rather
/// than implying this works like the rest of Send Abroad.
class WireTransferRequestScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String userAuthKey;
  const WireTransferRequestScreen({Key? key, required this.user, required this.userAuthKey})
      : super(key: key);

  @override
  State<WireTransferRequestScreen> createState() => _WireTransferRequestScreenState();
}

class _WireTransferRequestScreenState extends State<WireTransferRequestScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _beneficiaryNameController = TextEditingController();
  final TextEditingController _beneficiaryDetailsController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String _sourceCurrency = 'USD';
  String _destinationCurrency = 'USD';
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _submitted = false;

  // Confirmed from klasha.com/klashawire and support.klasha.com —
  // the destination (settlement) currencies KlashaWire pays out in.
  static const List<String> _destinationCurrencies = [
    'USD', 'EUR', 'GBP', 'CNY', 'INR', 'AUD', 'CAD', 'CHF', 'JPY', 'TRY',
  ];
  // Source (funding) currencies — the African currencies a merchant
  // wires from, per the same product pages.
  static const List<String> _sourceCurrencies = [
    'NGN', 'KES', 'GHS', 'USD', 'XAF', 'XOF', 'ZAR', 'UGX', 'TZS', 'RWF', 'ZMW',
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _beneficiaryNameController.dispose();
    _beneficiaryDetailsController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _isGuest => widget.user.isEmpty || widget.user['email'] == null;

  Future<void> _submit() async {
    if (_isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Create an account to request a wire transfer.")),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = "Enter a valid amount.");
      return;
    }
    if (amount < 500) {
      setState(() => _errorMessage = "KlashaWire transfers start at \$500.");
      return;
    }
    if (amount > 50000) {
      setState(() => _errorMessage = "KlashaWire transfers are capped at \$50,000 per transaction.");
      return;
    }
    if (_beneficiaryNameController.text.trim().isEmpty) {
      setState(() => _errorMessage = "Enter your supplier or beneficiary's name.");
      return;
    }
    if (_beneficiaryDetailsController.text.trim().isEmpty) {
      setState(() => _errorMessage = "Enter the beneficiary's bank details.");
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final result = await sendData(
      urlPath: "/api/v1/klasha/wire",
      data: {
        "amount": amount,
        "sourceCurrency": _sourceCurrency,
        "destinationCurrency": _destinationCurrency,
        "beneficiaryName": _beneficiaryNameController.text.trim(),
        "beneficiaryDetails": _beneficiaryDetailsController.text.trim(),
        "description": _descriptionController.text.trim(),
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['error'] != null || result['apiRequestError'] != null) {
      setState(() => _errorMessage =
          result['error']?.toString() ?? result['apiRequestError'].toString());
      return;
    }

    setState(() => _submitted = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return Scaffold(
        backgroundColor: AppColors.scaffold,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: AppColors.successBg, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Icon(Icons.check_rounded, color: AppColors.success, size: 36),
                  ),
                  const SizedBox(height: 18),
                  Text("Wire request received",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  const SizedBox(height: 8),
                  Text(
                    "Our team will process your request and follow up. Wire transfers settle in 1-4 business days, not instantly like mobile money or bank payouts.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                      ),
                      child: Text("Done", style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Wire transfer",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 19)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "For paying overseas suppliers in bulk — \$500 to \$50,000 per transfer, settling in 1-4 business days. This isn't instant like mobile money or bank transfers.",
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text("YOU SEND FROM",
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            _currencyDropdown(_sourceCurrencies, _sourceCurrency, (v) => setState(() => _sourceCurrency = v)),
            const SizedBox(height: 18),
            Text("AMOUNT",
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _amountController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: "500 – 50,000",
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text("SUPPLIER RECEIVES IN",
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            _currencyDropdown(
                _destinationCurrencies, _destinationCurrency, (v) => setState(() => _destinationCurrency = v)),
            const SizedBox(height: 18),
            Text("SUPPLIER / BENEFICIARY NAME",
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            _textField(_beneficiaryNameController, "e.g. Guangzhou Textiles Co."),
            const SizedBox(height: 18),
            Text("BENEFICIARY BANK DETAILS",
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            _textField(_beneficiaryDetailsController,
                "Bank name, account number, SWIFT/IBAN", maxLines: 3),
            const SizedBox(height: 18),
            Text("WHAT'S THIS FOR (OPTIONAL)",
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            _textField(_descriptionController, "e.g. Invoice #4471 — Q3 inventory order"),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                ),
                child: _isSubmitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text("Request wire transfer", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _currencyDropdown(List<String> options, String value, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
          items: options
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _textField(TextEditingController controller, String hint, {int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(fontSize: 14, color: AppColors.ink),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadii.md)),
        focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.primary, width: 1.6),
            borderRadius: BorderRadius.circular(AppRadii.md)),
        border: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadii.md)),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/african_country_data.dart';
import 'package:dutch_remit/utilities/custom_date_grouping.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/components/shared/transaction_receipt_dialog.dart';

/// Dutch Remit's own fee for issuing a card — separate from, and on
/// top of, the initial funding amount (see Backend/src/routes/cards.js).
const double kCardFeeOneTime = 3.5;
const double kCardFeeMonthly = 1.1;
const double kKycSkipFee = 1.5;
const double kInstantCardFee = 5.0;

/// The three card-creation tiers the user picks between before anything
/// else. See Backend/src/routes/cards.js for the matching server logic.
enum CardTier {
  /// Full KYC with a real uploaded document. Free (only the normal
  /// card-creation + funding fees apply).
  withKyc,

  /// No documents asked. idType is National_ID (African countries) or
  /// Passport (foreign), idNumber auto-generated server-side. +$1.50.
  withoutKyc,

  /// Issued instantly, no KYC or documents at all — the backend reuses
  /// or auto-provisions a cardholder behind the scenes. Flat $5.
  instant,
}

/// Real virtual card issuance via Eversend's documented Cards API
/// (POST /cards/user, then POST /cards — see Backend/src/routes/cards.js,
/// confirmed against https://eversend.readme.io/reference/create-a-card
/// and .../create-a-card-user). No raw card number ever touches this
/// app or its backend in either direction — Eversend generates and
/// holds the card; we only ever reference it by id.
///
/// Three real steps: identity (Eversend requires a one-time KYC
/// profile before it will issue anyone a card), design & funding,
/// then review & issue.
class CreateVirtualCardScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  const CreateVirtualCardScreen({Key? key, required this.user, this.userAuthKey}) : super(key: key);

  @override
  State<CreateVirtualCardScreen> createState() => _CreateVirtualCardScreenState();
}

class _CreateVirtualCardScreenState extends State<CreateVirtualCardScreen> {
  // _step == -1 is the tier picker, shown first. 0/1/2 are the existing
  // identity → design → review steps.
  int _step = -1;
  CardTier? _tier;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _cardUserId;

  // Step 1 — identity (required once by Eversend before any card can
  // be issued to this person).
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipController = TextEditingController();
  final _idNumberController = TextEditingController();
  AfricanCountryInfo _country = kAfricanCountries.first;
  String _idType = 'National_ID';
  bool _skipKyc = false;
  XFile? _idDocument;
  Uint8List? _idDocumentBytes;
  bool _isUploadingDocument = false;

  // Step 2 — design & funding.
  final _titleController = TextEditingController(text: 'My Dutch Remit Card');
  final _amountController = TextEditingController(text: '10');
  String _color = 'blue';
  String _brand = 'visa';
  String _currency = 'USD';
  // 'one_time' = $3.50 once, 'monthly' = $1.10/month — Dutch Remit's
  // own card-creation fee, on top of the funding amount above.
  String _cardFeeType = 'monthly';

  double get _cardCreationFee => _cardFeeType == 'one_time' ? kCardFeeOneTime : kCardFeeMonthly;
  double get _kycSkipFeeAmount => _skipKyc ? kKycSkipFee : 0;
  double get _totalFees => _tier == CardTier.instant
      ? kInstantCardFee
      : _cardCreationFee + _kycSkipFeeAmount;

  static const List<String> _colors = ['blue', 'black', 'purple', 'orange', 'yellow'];
  static const List<String> _idTypes = ['National_ID', 'Passport', 'Driving_License'];

  @override
  void initState() {
    super.initState();
    final first = widget.user['first_name']?.toString() ?? widget.user['fullname']?.toString().split(' ').first ?? '';
    final last = widget.user['last_name']?.toString() ?? '';
    _firstNameController.text = first;
    _lastNameController.text = last;
    _emailController.text = widget.user['email']?.toString() ?? '';
    _phoneController.text = widget.user['phone_number']?.toString() ?? '';
    _addressController.text = widget.user['address']?.toString() ?? '';
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _idNumberController.dispose();
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  bool get _identityComplete {
    final baseComplete = _firstNameController.text.trim().isNotEmpty &&
        _lastNameController.text.trim().isNotEmpty &&
        _emailController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty &&
        _addressController.text.trim().isNotEmpty &&
        _cityController.text.trim().isNotEmpty &&
        _stateController.text.trim().isNotEmpty &&
        _zipController.text.trim().isNotEmpty;
    if (!baseComplete) return false;
    // Skipping KYC needs nothing more — idType/idNumber are generated
    // server-side. Otherwise a real ID number AND an uploaded document
    // photo are both mandatory.
    if (_skipKyc) return true;
    return _idNumberController.text.trim().isNotEmpty && _idDocument != null;
  }

  Future<void> _pickIdDocument() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _idDocument = picked;
      _idDocumentBytes = bytes;
    });
  }

  Future<void> _submitIdentity() async {
    if (!_identityComplete) {
      setState(() => _errorMessage = _skipKyc
          ? "Please fill in every field above."
          : "Please fill in every field and upload a photo of your ID — these are required before we can issue your card.");
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    String? documentPath;
    if (!_skipKyc) {
      setState(() => _isUploadingDocument = true);
      final uploadResult = await sendData(
        urlPath: "/api/v1/cards/kyc-document",
        data: {
          "fileBase64": base64Encode(_idDocumentBytes!),
          "fileName": _idDocument!.name,
          "mimeType": _idDocument!.mimeType ?? 'application/octet-stream',
        },
        authKey: widget.userAuthKey,
      );
      if (!mounted) return;
      setState(() => _isUploadingDocument = false);

      if (uploadResult.containsKey('apiRequestError') || uploadResult['error'] != null) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = uploadResult['error']?.toString() ?? uploadResult['apiRequestError'].toString();
        });
        return;
      }
      documentPath = uploadResult['path']?.toString();
    }

    final result = await sendData(
      urlPath: "/api/v1/cards/user",
      data: {
        "firstName": _firstNameController.text.trim(),
        "lastName": _lastNameController.text.trim(),
        "email": _emailController.text.trim(),
        "phone": _phoneController.text.trim(),
        "country": _country.countryCode,
        "state": _stateController.text.trim(),
        "city": _cityController.text.trim(),
        "address": _addressController.text.trim(),
        "zipCode": _zipController.text.trim(),
        if (_skipKyc) "skipKyc": true,
        if (!_skipKyc) "idType": _idType,
        if (!_skipKyc) "idNumber": _idNumberController.text.trim(),
        if (!_skipKyc) "documentPath": documentPath,
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;

    if (result.containsKey('apiRequestError') || result['error'] != null) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = result['error']?.toString() ?? result['apiRequestError'].toString();
      });
      return;
    }

    setState(() {
      _isSubmitting = false;
      _cardUserId = (result['id'] ?? result['data']?['id'] ?? result['userId'])?.toString();
      _step = 1;
    });
  }

  Future<void> _issueCard() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (_titleController.text.trim().isEmpty || amount == null || amount <= 0) {
      setState(() => _errorMessage = "Enter a card name and a funding amount above 0.");
      return;
    }

    final bool isInstant = _tier == CardTier.instant;

    // The instant tier issues without a pre-created cardholder — the
    // backend resolves or auto-provisions one. Every other tier requires
    // the identity step to have run and produced a _cardUserId first.
    if (!isInstant && _cardUserId == null) {
      setState(() => _errorMessage = "Your identity profile wasn't saved correctly — go back and try again.");
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final result = await sendData(
      urlPath: isInstant ? "/api/v1/cards/instant" : "/api/v1/cards",
      data: isInstant
          ? {
              "title": _titleController.text.trim(),
              "color": _color,
              "brand": _brand,
              "amount": amount.toString(),
              "currency": _currency,
            }
          : {
              "title": _titleController.text.trim(),
              "color": _color,
              "brand": _brand,
              "amount": amount.toString(),
              "currency": _currency,
              "userId": _cardUserId,
              "cardFeeType": _cardFeeType,
              "skipKyc": _skipKyc,
            },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;

    if (result.containsKey('apiRequestError') || result['error'] != null) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = result['error']?.toString() ?? result['apiRequestError'].toString();
      });
      return;
    }

    final feeCharged = result['feeCharged'] is Map ? result['feeCharged'] as Map : null;
    final totalFee = double.tryParse(feeCharged?['totalFee']?.toString() ?? '') ?? _totalFees;
    final totalCharged = amount + totalFee;

    final now = DateTime.now();
    await SuccessfulTransactionsStorage().updateSuccessfulTransactions({
      'transactionMemberName': "Virtual card · ${_titleController.text.trim()}",
      'transactionAmount': totalCharged.toStringAsFixed(2),
      'transactionType': 'debit',
      'transactionDate': now.toIso8601String(),
      'dateGroup': customGroup(now),
      'paymentProvider': 'eversend',
      'cardCreationFee': totalFee.toStringAsFixed(2),
    });

    if (!mounted) return;
    Provider.of<UserLoginStateProvider>(context, listen: false)
        .updateBankBalance('debit', totalCharged.toStringAsFixed(2));

    setState(() {
      _isSubmitting = false;
      _step = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Create a Virtual Card",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 17)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_step >= 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Row(
                  children: List.generate(3, (i) {
                    final bool done = i <= _step;
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
                        height: 4,
                        decoration: BoxDecoration(
                          color: done ? AppColors.primary : AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(key: ValueKey(_step), child: _buildStep()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Selects a tier and advances. With-KYC and without-KYC both go into
  /// the normal wizard (they only differ by whether documents are asked
  /// for). Instant skips the wizard entirely and issues immediately.
  void _selectTier(CardTier tier) {
    setState(() {
      _tier = tier;
      _errorMessage = null;
      if (tier == CardTier.withKyc) {
        _skipKyc = false;
        _step = 0;
      } else if (tier == CardTier.withoutKyc) {
        _skipKyc = true;
        _step = 0;
      } else {
        // Instant — no identity step needed at all.
        _skipKyc = true;
        _step = 1; // straight to design & funding
      }
    });
  }

  Widget _stepTierPicker() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text("Choose how to create your card",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 6),
        Text(
            "You'll need to verify your details (create a cardholder) before a card can be issued. Pick the option that suits you.",
            style: TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.inkMuted)),
        const SizedBox(height: 20),
        _tierCard(
          tier: CardTier.withKyc,
          icon: Icons.verified_user_rounded,
          accent: AppColors.success,
          title: "With verification",
          price: "Free",
          blurb:
              "Upload a valid ID document. Standard verification — no extra fee beyond the normal card cost.",
        ),
        const SizedBox(height: 12),
        _tierCard(
          tier: CardTier.withoutKyc,
          icon: Icons.flash_auto_rounded,
          accent: AppColors.primary,
          title: "Without verification",
          price: "+\$${kKycSkipFee.toStringAsFixed(2)}",
          blurb:
              "Skip document upload. We complete verification for you automatically — National ID for African countries, Passport elsewhere.",
        ),
        const SizedBox(height: 12),
        _tierCard(
          tier: CardTier.instant,
          icon: Icons.bolt_rounded,
          accent: const Color(0xFFF5B841),
          title: "Instant card",
          price: "\$${kInstantCardFee.toStringAsFixed(2)}",
          blurb:
              "Issued immediately. No documents, no verification steps — your cardholder is set up automatically behind the scenes.",
        ),
      ],
    );
  }

  Widget _tierCard({
    required CardTier tier,
    required IconData icon,
    required Color accent,
    required String title,
    required String price,
    required String blurb,
  }) {
    return InkWell(
      onTap: () => _selectTier(tier),
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: TextStyle(
                                fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.ink)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(price,
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w800, color: accent)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(blurb,
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.inkMuted)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case -1:
        return _stepTierPicker();
      case 0:
        return _stepIdentity();
      case 1:
        return _stepDesignAndFund();
      default:
        return _stepSuccess();
    }
  }

  InputDecoration _dec(String hint) => InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadii.md)),
        focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.primary, width: 1.6), borderRadius: BorderRadius.circular(AppRadii.md)),
        border: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadii.md)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 14),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
      );

  Widget _stepIdentity() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text("Step 1 of 3", style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text("Confirm your identity", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 6),
        Text("We require this once before issuing a card to you.",
            style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
        _label("FIRST NAME"),
        TextField(controller: _firstNameController, decoration: _dec("John")),
        _label("LAST NAME"),
        TextField(controller: _lastNameController, decoration: _dec("Doe")),
        _label("EMAIL"),
        TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: _dec("john@example.com")),
        _label("PHONE"),
        TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: _dec("+256712345678")),
        _label("COUNTRY"),
        InkWell(
          onTap: () async {
            final picked = await showModalBottomSheet<AfricanCountryInfo>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
              builder: (sheetContext) => SafeArea(
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: ListView.builder(
                    itemCount: kAfricanCountries.length,
                    itemBuilder: (context, index) {
                      final c = kAfricanCountries[index];
                      return ListTile(
                        leading: Text(c.flagEmoji, style: TextStyle(fontSize: 20)),
                        title: Text(c.countryName),
                        onTap: () => Navigator.of(sheetContext).pop(c),
                      );
                    },
                  ),
                ),
              ),
            );
            if (picked != null) setState(() => _country = picked);
          },
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              Text(_country.flagEmoji, style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(child: Text(_country.countryName, style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600))),
              Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
            ]),
          ),
        ),
        _label("STATE / DISTRICT"),
        TextField(controller: _stateController, decoration: _dec("e.g. Lagos, Kampala")),
        _label("CITY"),
        TextField(controller: _cityController, decoration: _dec("e.g. Ikeja, Nakawa")),
        _label("ADDRESS"),
        TextField(controller: _addressController, decoration: _dec("Street address")),
        _label("ZIP / POSTAL CODE"),
        TextField(controller: _zipController, decoration: _dec("100001")),
        if (!_skipKyc) ...[
          _label("ID TYPE"),
          Row(
            children: _idTypes.map((t) {
              final bool isActive = _idType == t;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: t == _idTypes.last ? 0 : 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _idType = t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.ink : Colors.white,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        border: Border.all(color: isActive ? AppColors.ink : AppColors.border),
                      ),
                      child: Text(t.replaceAll('_', ' '),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: isActive ? Colors.white : AppColors.inkMuted)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          _label("ID NUMBER"),
          TextField(controller: _idNumberController, decoration: _dec("123456789012")),
          _label("ID DOCUMENT (required)"),
          InkWell(
            onTap: _isUploadingDocument ? null : _pickIdDocument,
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: _idDocument == null ? AppColors.danger.withOpacity(0.4) : AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    _idDocument != null ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                    color: _idDocument != null ? AppColors.success : AppColors.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _idDocument != null ? _idDocument!.name : "Upload a photo of your ID",
                      style: TextStyle(
                          color: _idDocument != null ? AppColors.ink : AppColors.textMuted,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_isUploadingDocument)
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        InkWell(
          onTap: () => setState(() => _skipKyc = !_skipKyc),
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _skipKyc ? AppColors.primary.withOpacity(0.06) : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: _skipKyc ? AppColors.primary : Colors.transparent),
            ),
            child: Row(
              children: [
                Switch(
                  value: _skipKyc,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() => _skipKyc = v),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("I don't have an ID to upload",
                          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(
                        "Proceed without KYC for an extra \$${kKycSkipFee.toStringAsFixed(2)} fee.",
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitIdentity,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: _isSubmitting
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : Text("Continue", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _stepDesignAndFund() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text("Step 2 of 3", style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text("Design your card", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
        _label("CARD NAME"),
        TextField(controller: _titleController, decoration: _dec("e.g. My Dutch Remit Card")),
        _label("BRAND"),
        Row(
          children: ['visa', 'mastercard'].map((b) {
            final bool isActive = _brand == b;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: b == 'visa' ? 8 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _brand = b),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.ink : Colors.white,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(color: isActive ? AppColors.ink : AppColors.border),
                    ),
                    child: Text(b[0].toUpperCase() + b.substring(1),
                        style: TextStyle(fontWeight: FontWeight.w700, color: isActive ? Colors.white : AppColors.inkMuted)),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        _label("COLOR"),
        Wrap(
          spacing: 10,
          children: _colors.map((c) {
            final bool isActive = _color == c;
            return GestureDetector(
              onTap: () => setState(() => _color = c),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _colorFor(c),
                  shape: BoxShape.circle,
                  border: isActive ? Border.all(color: AppColors.ink, width: 2.5) : null,
                ),
                child: isActive ? Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
              ),
            );
          }).toList(),
        ),
        _label("FUND FROM"),
        Row(
          children: ['USD', 'EUR', 'GBP'].map((c) {
            final bool isActive = _currency == c;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _currency = c),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.ink : AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(c, style: TextStyle(fontWeight: FontWeight.w700, color: isActive ? Colors.white : AppColors.inkMuted)),
                ),
              ),
            );
          }).toList(),
        ),
        _label("INITIAL FUNDING AMOUNT"),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: _dec("10"),
          onChanged: (_) => setState(() {}),
        ),
        if (_tier != CardTier.instant) ...[
          _label("CARD CREATION FEE"),
          Row(
            children: [
              Expanded(
                child: _feeOption(
                    label: "One-time", price: "\$${kCardFeeOneTime.toStringAsFixed(2)}", value: 'one_time'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _feeOption(
                    label: "Monthly", price: "\$${kCardFeeMonthly.toStringAsFixed(2)}/mo", value: 'monthly'),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _feeRow("Funding amount",
                  "${(double.tryParse(_amountController.text.trim()) ?? 0).toStringAsFixed(2)} $_currency"),
              if (_tier == CardTier.instant)
                _feeRow("Instant card fee", "\$${kInstantCardFee.toStringAsFixed(2)}")
              else ...[
                _feeRow(_cardFeeType == 'one_time' ? "Card fee (one-time)" : "Card fee (first month)",
                    "\$${_cardCreationFee.toStringAsFixed(2)}"),
                if (_skipKyc) _feeRow("No-KYC fee", "\$${_kycSkipFeeAmount.toStringAsFixed(2)}"),
              ],
              Divider(color: AppColors.divider, height: 18),
              _feeRow(
                "Total charged today",
                "\$${((double.tryParse(_amountController.text.trim()) ?? 0) + _totalFees).toStringAsFixed(2)}",
                bold: true,
              ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step = _tier == CardTier.instant ? -1 : 0),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                ),
                child: Text("Back", style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _issueCard,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                ),
                child: _isSubmitting
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : Text("Issue card", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _feeOption({required String label, required String price, required String value}) {
    final bool isActive = _cardFeeType == value;
    return GestureDetector(
      onTap: () => setState(() => _cardFeeType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? AppColors.ink : Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: isActive ? AppColors.ink : AppColors.border),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.white70 : AppColors.textMuted)),
            const SizedBox(height: 2),
            Text(price,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: isActive ? Colors.white : AppColors.ink)),
          ],
        ),
      ),
    );
  }

  Widget _feeRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: bold ? 13.5 : 12.5,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: bold ? AppColors.ink : AppColors.textMuted)),
            Text(value,
                style: TextStyle(
                    fontSize: bold ? 13.5 : 12.5,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: AppColors.ink)),
          ],
        ),
      );

  Color _colorFor(String name) {
    switch (name) {
      case 'black':
        return Colors.black87;
      case 'purple':
        return Colors.deepPurple;
      case 'orange':
        return Colors.deepOrange;
      case 'yellow':
        return Colors.amber;
      default:
        return AppColors.primary;
    }
  }

  Widget _stepSuccess() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56),
        const SizedBox(height: 16),
        Text("Your card is ready", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 8),
        Text("You can use it right away for online payments and subscriptions.",
            style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
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
    );
  }
}

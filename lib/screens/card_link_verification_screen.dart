import 'package:flutter/material.dart';
import 'package:dutch_remit/components/wallet_screen/add_card_screen.dart';
import 'package:dutch_remit/screens/create_virtual_card_screen.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/utilities/slide_right_route.dart';

/// Step 1 of linking an existing card: confirm you already have a
/// Dutch Remit card, verify your identity, and accept the $2.10
/// retrieval fee — before AddCardScreen ever asks for the card
/// number itself. See Backend/src/routes/cards.js POST /link.
class CardLinkVerificationScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  const CardLinkVerificationScreen({Key? key, required this.user, this.userAuthKey}) : super(key: key);

  @override
  State<CardLinkVerificationScreen> createState() => _CardLinkVerificationScreenState();
}

class _CardLinkVerificationScreenState extends State<CardLinkVerificationScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  bool _isChecking = true;
  bool _isEligible = false;
  bool _isContinuing = false;
  String? _errorMessage;

  static const double kCardLinkFee = 2.1;

  @override
  void initState() {
    super.initState();
    final first = widget.user['first_name']?.toString() ??
        widget.user['fullname']?.toString().split(' ').first ??
        '';
    final last = widget.user['last_name']?.toString() ?? '';
    _firstNameController.text = first;
    _lastNameController.text = last;
    _emailController.text = widget.user['email']?.toString() ?? '';
    _phoneController.text = widget.user['phone_number']?.toString() ?? '';
    _addressController.text = widget.user['address']?.toString() ?? '';
    _checkEligibility();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _checkEligibility() async {
    final result = await getData(urlPath: "/api/v1/cards/mine", authKey: widget.userAuthKey);
    if (!mounted) return;
    final cards = result['cards'] is List ? List<Map<String, dynamic>>.from(result['cards']) : [];
    setState(() {
      _isChecking = false;
      _isEligible = cards.any((c) => c['source'] == 'issued');
    });
  }

  bool get _identityComplete =>
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty &&
      _emailController.text.trim().isNotEmpty &&
      _phoneController.text.trim().isNotEmpty &&
      _addressController.text.trim().isNotEmpty;

  void _continue() {
    if (!_identityComplete) {
      setState(() => _errorMessage = "Please fill in every field.");
      return;
    }
    setState(() => _errorMessage = null);
    Navigator.push(
      context,
      SlideRightRoute(
        page: AddCardScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          identity: {
            'firstName': _firstNameController.text.trim(),
            'lastName': _lastNameController.text.trim(),
            'email': _emailController.text.trim(),
            'phone': _phoneController.text.trim(),
            'address': _addressController.text.trim(),
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Add a Card",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 17)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: _isChecking
            ? Center(child: CircularProgressIndicator(color: AppColors.primary))
            : !_isEligible
                ? _buildIneligible()
                : _buildForm(),
      ),
    );
  }

  Widget _buildIneligible() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.credit_card_off_outlined, size: 44, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text("You need a Dutch Remit card first",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16)),
          const SizedBox(height: 6),
          Text("Create a Dutch Remit card before you can link an existing one as a funding source.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              SlideRightRoute(
                  page: CreateVirtualCardScreen(user: widget.user, userAuthKey: widget.userAuthKey)),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: Text("Create a card", style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text("Verify your identity",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 6),
        Text("We confirm this before retrieving and linking your card.",
            style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
        _label("FIRST NAME"),
        TextField(controller: _firstNameController, decoration: _dec("John")),
        _label("LAST NAME"),
        TextField(controller: _lastNameController, decoration: _dec("Doe")),
        _label("EMAIL"),
        TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: _dec("john@example.com")),
        _label("PHONE"),
        TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: _dec("+256712345678")),
        _label("ADDRESS"),
        TextField(controller: _addressController, decoration: _dec("Street address")),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "A \$${kCardLinkFee.toStringAsFixed(2)} card retrieval fee applies once your card is linked.",
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                ),
              ),
            ],
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
            onPressed: _continue,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: Text("Continue", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
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
}

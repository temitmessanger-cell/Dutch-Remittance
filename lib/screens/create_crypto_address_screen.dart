import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';

/// Collects the two fields Eversend's POST /crypto/addresses actually
/// requires beyond the coin itself — ownerName and
/// destinationAddressDescription — pre-filled from the signed-in
/// user's profile where available but always editable, then creates
/// the address. Reached only from CryptoScreen's coin picker, after
/// the real existence check already confirmed the user has no address
/// for this coin yet.
class CreateCryptoAddressScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  final Map<String, dynamic> coin;

  const CreateCryptoAddressScreen({
    Key? key,
    required this.user,
    required this.userAuthKey,
    required this.coin,
  }) : super(key: key);

  @override
  State<CreateCryptoAddressScreen> createState() => _CreateCryptoAddressScreenState();
}

class _CreateCryptoAddressScreenState extends State<CreateCryptoAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ownerNameController;
  late final TextEditingController _descriptionController;

  bool _isCreating = false;
  String? _errorMessage;
  Map<String, dynamic>? _createdAddress;

  @override
  void initState() {
    super.initState();
    final firstName = widget.user['first_name']?.toString() ?? '';
    final lastName = widget.user['last_name']?.toString() ?? '';
    _ownerNameController = TextEditingController(text: [firstName, lastName].where((s) => s.isNotEmpty).join(' '));
    _descriptionController = TextEditingController(text: widget.user['email']?.toString() ?? '');
  }

  @override
  void dispose() {
    _ownerNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createAddress() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    final result = await sendData(
      urlPath: "/api/v1/crypto/addresses",
      data: {
        "coin": widget.coin['coin'],
        "ownerName": _ownerNameController.text.trim(),
        "destinationAddressDescription": _descriptionController.text.trim(),
      },
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;

    if (result['error'] != null || result['apiRequestError'] != null) {
      setState(() {
        _isCreating = false;
        _errorMessage = result['error']?.toString() ??
            result['apiRequestError']?.toString() ??
            "Couldn't create your address right now. Please try again.";
      });
      return;
    }

    setState(() {
      _isCreating = false;
      _createdAddress = result;
    });
  }

  void _copyAddress() {
    final addr = _createdAddress?['address']?.toString();
    if (addr == null) return;
    Clipboard.setData(ClipboardData(text: addr));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Address copied"), backgroundColor: AppColors.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coinCode = widget.coin['coin']?.toString() ?? '';
    final coinName = widget.coin['name']?.toString() ?? '';

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Create $coinCode address",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: _createdAddress != null ? _buildSuccessState(coinCode) : _buildForm(coinCode, coinName),
      ),
    );
  }

  Widget _buildForm(String coinCode, String coinName) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
              Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "We just need a couple of details to generate your $coinName ($coinCode) deposit address.",
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("FULL NAME",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _ownerNameController,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your full name' : null,
                decoration: _fieldDecoration("Your full name"),
              ),
              const SizedBox(height: 18),
              Text("EMAIL OR UNIQUE ID",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Text("Used to label this address on your account — usually your email.",
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your email or a unique ID' : null,
                decoration: _fieldDecoration("you@example.com"),
              ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isCreating ? null : _createAddress,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: _isCreating
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text("Create address", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState(String coinCode) {
    final addr = _createdAddress?['address']?.toString() ?? '—';
    final network = _createdAddress?['network']?.toString() ?? coinCode;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.successBg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(Icons.check_rounded, color: AppColors.success, size: 32),
          ),
        ),
        const SizedBox(height: 18),
        Text("Your $coinCode address is ready",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 6),
        Text("Send only $coinCode on the $network network to this address.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("ADDRESS",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.md)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(addr, style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: AppColors.ink)),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy_rounded, size: 18, color: AppColors.primary),
                      onPressed: _copyAddress,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                "Sending any other asset, or using the wrong network, may result in permanent loss.",
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
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
            child: Text("Done", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadii.md)),
      focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary, width: 1.6),
          borderRadius: BorderRadius.circular(AppRadii.md)),
      errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.danger), borderRadius: BorderRadius.circular(AppRadii.md)),
      border: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadii.md)),
    );
  }
}

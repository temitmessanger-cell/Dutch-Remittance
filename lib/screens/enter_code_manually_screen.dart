import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dutch_remit/screens/fund_transfer_screen.dart';
import 'package:dutch_remit/utilities/slide_right_route.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// The "scan" alternative for a web app with no reliable camera access:
/// the user pastes or types the code shown on someone else's "My QR
/// Code" screen (or that another phone's camera decoded into text),
/// and this validates + routes into the same real FundTransferScreen
/// a successful camera scan would have used.
class EnterCodeManuallyScreen extends StatefulWidget {
  const EnterCodeManuallyScreen({Key? key}) : super(key: key);

  @override
  State<EnterCodeManuallyScreen> createState() => _EnterCodeManuallyScreenState();
}

class _EnterCodeManuallyScreenState extends State<EnterCodeManuallyScreen> {
  final TextEditingController _codeController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _tryProceeding() {
    final raw = _codeController.text.trim();
    if (raw.isEmpty) {
      setState(() => _errorMessage = "Paste or type a code first.");
      return;
    }

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw FormatException();
      data = Map<String, dynamic>.from(decoded);
    } catch (e) {
      setState(() => _errorMessage = "That code isn't valid. Double-check and try again.");
      return;
    }

    // Same validation the original camera scanner used: requires enough
    // recognized fields to be confident this is really a Dutch Remit
    // payment code, not arbitrary pasted text.
    const validKeys = {
      'avatar',
      'homepage',
      'name',
      'walletAddress',
      'emailAddress',
      'phoneNumber',
      'communicationAddress',
    };
    final matchedFields = validKeys.intersection(data.keys.toSet()).length;

    if (matchedFields < 2 || data['name'] == null) {
      setState(() => _errorMessage =
          "That code doesn't look like a Dutch Remit payment code.");
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
    Navigator.push(
        context,
        SlideRightRoute(
            page: FundTransferScreen(otherParty: data, transactionType: 'debit')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Enter code",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Paste the code from someone's \"My QR Code\" screen to send them money.",
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                minLines: 3,
                maxLines: 6,
                style: TextStyle(fontSize: 14, color: AppColors.ink),
                decoration: InputDecoration(
                  hintText: "Paste code here",
                  filled: true,
                  fillColor: AppColors.surfaceAlt,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      borderSide: BorderSide.none),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _tryProceeding,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md)),
                  ),
                  child: Text("Continue",
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

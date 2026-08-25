import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// Shows the user's own payment-request QR code. Encodes the same field
/// shape FundTransferScreen and the contacts list already expect
/// (name, emailAddress, phoneNumber, walletAddress), so any code
/// generated here can be entered via EnterCodeManuallyScreen — or
/// scanned by an external QR app — and lead straight into a real,
/// working transfer flow.
///
/// Built with qr_flutter rather than a camera-based scanner: it's pure
/// Dart rendering with no native platform view, so it actually works on
/// Flutter web (this app's primary target), where camera-based QR
/// scanning packages are unreliable or unsupported.
class MyQrCodeScreen extends StatelessWidget {
  final Map<String, dynamic> user;
  const MyQrCodeScreen({Key? key, required this.user}) : super(key: key);

  String get _displayName {
    final first = user['first_name']?.toString().trim() ?? '';
    final last = user['last_name']?.toString().trim() ?? '';
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    return user['username']?.toString() ?? 'Dutch Remit User';
  }

  String get _qrPayload {
    final payload = {
      'name': _displayName,
      if (user['email'] != null) 'emailAddress': user['email'],
      if (user['phone_number'] != null) 'phoneNumber': user['phone_number'],
      if (user['walletAddress'] != null) 'walletAddress': user['walletAddress'],
      if (user['uid'] != null) 'communicationAddress': user['uid'],
    };
    return jsonEncode(payload);
  }

  @override
  Widget build(BuildContext context) {
    final bool isGuest = user.isEmpty || user['email'] == null;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("My QR Code",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: isGuest
            ? _buildGuestState(context)
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        boxShadow: AppShadows.raised,
                      ),
                      child: QrImageView(
                        data: _qrPayload,
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                        eyeStyle: QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: AppColors.primary,
                        ),
                        dataModuleStyle: QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(_displayName,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        "Let someone scan this to send you money instantly.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildGuestState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_2_rounded, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text("Create an account to get your QR code",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              "Guests don't have a payment profile yet, so there's nothing to encode.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

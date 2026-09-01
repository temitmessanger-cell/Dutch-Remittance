import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/components/main_app_screen/tabbed_layout_component.dart';
import 'package:dutch_remit/components/shared/phone_number_field.dart';
import 'package:dutch_remit/database/cards_storage.dart';
import 'package:dutch_remit/database/login_info_storage.dart';
import 'package:dutch_remit/database/hadwin_user_device_info_storage.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/database/user_data_storage.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/screens/onboarding_screen.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// Passwordless phone login: real Eversend WhatsApp OTP
/// (POST /api/v1/auth/phone-otp/request, code_type: "whatsapp" — the
/// same confirmed mechanism used for deposit-confirmation OTPs) as
/// the verification step, with zero real money movement anywhere in
/// the flow — the backend never attempts a collection/charge to
/// verify the code; it only matches the phone against a server-side
/// pinId the client never sees. See Backend/src/routes/auth.js's
/// phone-otp/request and phone-otp/verify for the full design
/// reasoning.
class PhoneLoginFormComponent extends StatefulWidget {
  const PhoneLoginFormComponent({Key? key}) : super(key: key);

  @override
  State<PhoneLoginFormComponent> createState() => _PhoneLoginFormComponentState();
}

class _PhoneLoginFormComponentState extends State<PhoneLoginFormComponent> {
  LoginInfoStorage loginInfoStorage = LoginInfoStorage();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  String _fullPhoneNumber = '';

  bool _codeSent = false;
  bool _isSendingCode = false;
  bool _isVerifying = false;
  String phoneErrorMessage = "";
  String codeErrorMessage = "";

  static const _resendCooldownSeconds = 60;
  int _resendCooldown = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCooldown = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  Future<bool> _saveLoggedInUserData(
      String loggedInUserAuthKey, Map<String, dynamic> user) async {
    try {
      final userIsSaved = await Future.wait([
        UserDataStorage().saveUserData(user),
        loginInfoStorage.setPersistentLoginData(
            user['id'].toString(), loggedInUserAuthKey)
      ]);

      if (mounted) {
        Provider.of<UserLoginStateProvider>(context, listen: false)
            .setAuthKeyValue(loggedInUserAuthKey);
        Provider.of<UserLoginStateProvider>(context, listen: false)
            .initializeBankBalance(user);
      }

      return userIsSaved[0] && userIsSaved[1];
    } catch (e) {
      return false;
    }
  }

  void _requestCode() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_fullPhoneNumber.isEmpty || !_fullPhoneNumber.startsWith('+')) {
      setState(() => phoneErrorMessage = 'Enter your phone number');
      return;
    }
    setState(() => phoneErrorMessage = "");

    setState(() => _isSendingCode = true);
    final response = await sendData(
      urlPath: "/api/v1/auth/phone-otp/request",
      data: {"phone": _fullPhoneNumber},
    );
    if (!mounted) return;
    setState(() => _isSendingCode = false);

    if (response.keys.join().toLowerCase().contains("error")) {
      setState(() => phoneErrorMessage =
          response['error']?.toString() ?? "Couldn't send a code. Please try again.");
      return;
    }

    setState(() {
      _codeSent = true;
      codeErrorMessage = "";
    });
    _startResendCooldown();
  }

  void _verifyCodeAndLogIn() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_codeController.text.trim().isEmpty) {
      setState(() => codeErrorMessage = 'Enter the code we sent to your WhatsApp');
      return;
    }

    setState(() {
      _isVerifying = true;
      codeErrorMessage = "";
    });

    final dataReceived = await sendData(
      urlPath: "/api/v1/auth/phone-otp/verify",
      data: {
        "phone": _fullPhoneNumber,
        "pin": _codeController.text.trim(),
      },
    );

    if (!mounted) return;

    if (dataReceived.keys.join().toLowerCase().contains("error")) {
      setState(() => _isVerifying = false);
      setState(() => codeErrorMessage =
          dataReceived['error']?.toString() ?? "That code is invalid or has expired.");
      return;
    }

    final status = await Future.wait([
      _saveLoggedInUserData(
          dataReceived['authorization_token'], dataReceived['user']),
      CardsStorage()
          .initializeAvailableCards(dataReceived['authorization_token']),
      SuccessfulTransactionsStorage().initializeSuccessfulTransactions()
    ]);

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (status[0] == true && status[1] == true && status[2] == true) {
      final alreadyOnboarded = await UserDeviceInfoStorage().wasUsedBefore;
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(
              content: Text("Login Successful"),
              backgroundColor: AppColors.success))
          .closed
          .then((value) => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => alreadyOnboarded
                      ? TabbedLayoutComponent(userData: dataReceived['user'])
                      : OnboardingScreen(userData: dataReceived['user'])),
              (route) => false));
    }
  }

  void _changePhone() {
    _resendTimer?.cancel();
    setState(() {
      _codeSent = false;
      _codeController.clear();
      codeErrorMessage = "";
      _resendCooldown = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: EdgeInsets.symmetric(vertical: 6),
          child: PhoneNumberField(
            controller: _phoneController,
            hintText: "Phone number",
            onChanged: (fullNumber) => setState(() => _fullPhoneNumber = fullNumber),
          ),
        ),
        if (phoneErrorMessage != '')
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              phoneErrorMessage,
              style: TextStyle(fontSize: 12.5, color: AppColors.danger),
            ),
          ),
        if (_codeSent) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  "Check WhatsApp on $_fullPhoneNumber for your 6-digit code from Eversend.",
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ),
              TextButton(
                onPressed: _changePhone,
                child: Text('Change',
                    style: TextStyle(color: AppColors.primary, fontSize: 13)),
              ),
            ],
          ),
          Container(
            child: TextFormField(
              controller: _codeController,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (value) => _verifyCodeAndLogIn(),
              keyboardType: TextInputType.number,
              autocorrect: false,
              decoration: InputDecoration(
                fillColor: AppColors.surfaceAlt,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                hintText: "Code from WhatsApp",
                hintStyle: TextStyle(fontSize: 15, color: AppColors.textMuted),
              ),
              style: TextStyle(fontSize: 16, color: AppColors.ink),
            ),
            margin: EdgeInsets.symmetric(vertical: 6),
          ),
          if (codeErrorMessage != '')
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(
                codeErrorMessage,
                style: TextStyle(fontSize: 12.5, color: AppColors.danger),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: (_isSendingCode || _resendCooldown > 0)
                  ? null
                  : _requestCode,
              child: Text(
                _resendCooldown > 0
                    ? 'Resend code in ${_resendCooldown}s'
                    : 'Resend code',
                style: TextStyle(
                    fontSize: 13,
                    color: _resendCooldown > 0
                        ? AppColors.textMuted
                        : AppColors.primary),
              ),
            ),
          ),
        ],
        Container(
          margin: EdgeInsets.symmetric(vertical: 16.0),
          width: double.infinity,
          height: 58,
          child: ElevatedButton(
              onPressed: (_isSendingCode || _isVerifying)
                  ? null
                  : (_codeSent ? _verifyCodeAndLogIn : _requestCode),
              child: (_isSendingCode || _isVerifying)
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : Text(
                      _codeSent ? 'Verify & log in' : 'Send code',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md)),
              )),
        ),
      ],
    );
  }
}

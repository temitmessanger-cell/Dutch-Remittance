import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dutch_remit/components/main_app_screen/tabbed_layout_component.dart';
import 'package:dutch_remit/database/cards_storage.dart';
import 'package:dutch_remit/database/login_info_storage.dart';
import 'package:dutch_remit/database/hadwin_user_device_info_storage.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/database/user_data_storage.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/screens/onboarding_screen.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/utilities/display_error_alert.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// Passwordless login: enter an email, we send a Supabase email OTP,
/// then the code is verified server-side and swapped for a real
/// Supabase session — no password anywhere in this flow.
class LoginFormComponent extends StatefulWidget {
  const LoginFormComponent({Key? key}) : super(key: key);

  @override
  LoginFormComponentState createState() {
    return LoginFormComponentState();
  }
}

class LoginFormComponentState extends State<LoginFormComponent> {
  LoginInfoStorage loginInfoStorage = LoginInfoStorage();
  final _emailFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  RegExp validEmailFormat = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");

  bool _codeSent = false;
  bool _isSendingCode = false;
  bool _isVerifying = false;
  String emailErrorMessage = "";
  String codeErrorMessage = "";

  static const _resendCooldownSeconds = 60;
  int _resendCooldown = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _emailController.dispose();
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
    if (!_emailFormKey.currentState!.validate() || emailErrorMessage != '') {
      return;
    }

    setState(() => _isSendingCode = true);
    final response = await sendData(
      urlPath: "/api/v1/auth/otp/request",
      data: {"email": _emailController.text.trim(), "purpose": "login"},
    );
    if (!mounted) return;
    setState(() => _isSendingCode = false);

    if (response.keys.join().toLowerCase().contains("error")) {
      showErrorAlert(context, response);
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
      setState(() => codeErrorMessage = 'Enter the code we emailed you');
      return;
    }

    setState(() {
      _isVerifying = true;
      codeErrorMessage = "";
    });

    final dataReceived = await sendData(
      urlPath: "/api/v1/auth/otp/verify",
      data: {
        "email": _emailController.text.trim(),
        "token": _codeController.text.trim(),
      },
    );

    if (!mounted) return;

    if (dataReceived.keys.join().toLowerCase().contains("error")) {
      setState(() => _isVerifying = false);
      showErrorAlert(context, dataReceived);
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
      // First-ever launch: onboarding hasn't been shown yet, so route
      // through it now (it forwards to the main app once finished).
      // Any later login from a returning user skips straight to the
      // main app, exactly as before.
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

  void _changeEmail() {
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
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            child: TextFormField(
              controller: _emailController,
              enabled: !_codeSent,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _requestCode(),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  setState(() =>
                      emailErrorMessage = 'you must provide your email address');
                } else if (!validEmailFormat.hasMatch(value.trim())) {
                  setState(() =>
                      emailErrorMessage = 'format of your email address is invalid');
                } else {
                  setState(() => emailErrorMessage = "");
                }
                return null;
              },
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
                hintText: "Email address",
                hintStyle: TextStyle(fontSize: 15, color: AppColors.textMuted),
                suffixIcon: _codeSent
                    ? TextButton(
                        onPressed: _changeEmail,
                        child: Text('Change',
                            style: TextStyle(color: AppColors.primary)),
                      )
                    : null,
              ),
              style: TextStyle(fontSize: 16, color: AppColors.ink),
            ),
            margin: EdgeInsets.symmetric(vertical: 6),
          ),
          if (emailErrorMessage != '')
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(
                emailErrorMessage,
                style: TextStyle(fontSize: 12.5, color: AppColors.danger),
              ),
            ),
          if (_codeSent) ...[
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
                  hintText: "Code we emailed you",
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
      ),
    );
  }
}

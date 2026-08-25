import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/utilities/display_error_alert.dart';

/// Final sign-up step: email + Supabase email OTP. No password field —
/// entering the correct code both confirms the address and finishes
/// account creation in one step (the backend upserts the profile with
/// the name/address collected in the previous step, then returns a
/// real Supabase session).
class StepGetEmailOtp extends StatefulWidget {
  final LabeledGlobalKey<FormState> emailOtpFormKey;
  final Function updateSignUpDetails;
  final Function registrationDetails;

  /// Called with the backend's { authorization_token, user } response
  /// once the code is verified and the account is fully created.
  final void Function(Map<String, dynamic> response) onAccountCreated;

  const StepGetEmailOtp({
    Key? key,
    required this.updateSignUpDetails,
    required this.registrationDetails,
    required this.emailOtpFormKey,
    required this.onAccountCreated,
  }) : super(key: key);

  @override
  _StepGetEmailOtpState createState() => _StepGetEmailOtpState();
}

class _StepGetEmailOtpState extends State<StepGetEmailOtp> {
  final _codeController = TextEditingController();
  String emailId = "";
  String emailIdErrorMessage = "";
  String codeErrorMessage = "";
  bool _codeSent = false;
  bool _isSendingCode = false;
  bool _isVerifying = false;
  RegExp validEmailFormat = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");

  static const _resendCooldownSeconds = 60;
  int _resendCooldown = 0;
  Timer? _resendTimer;

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

  @override
  void initState() {
    super.initState();
    Map<String, String> signUpDetails = widget.registrationDetails();
    if (mounted) {
      setState(() {
        emailId = signUpDetails['emailId']!;
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _sendCode() async {
    if (!widget.emailOtpFormKey.currentState!.validate() ||
        emailIdErrorMessage != '') {
      return;
    }

    setState(() => _isSendingCode = true);
    final response = await sendData(
      urlPath: "/api/v1/auth/otp/request",
      data: {"email": emailId, "purpose": "signup"},
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

  void _verifyCode() async {
    if (_codeController.text.trim().isEmpty) {
      setState(() => codeErrorMessage = 'Enter the code we emailed you');
      return;
    }

    setState(() {
      _isVerifying = true;
      codeErrorMessage = "";
    });

    final signUpDetails = widget.registrationDetails();
    final response = await sendData(
      urlPath: "/api/v1/auth/otp/verify",
      data: {
        "email": emailId,
        "token": _codeController.text.trim(),
        "fullname": signUpDetails['fullname'],
        "address": signUpDetails['address'],
      },
    );

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (response.keys.join().toLowerCase().contains("error")) {
      showErrorAlert(context, response);
      return;
    }

    widget.onAccountCreated(response);
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
        key: widget.emailOtpFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              child: TextFormField(
                initialValue: emailId,
                enabled: !_codeSent,
                validator: _validateEmailId,
                autofocus: mounted,
                autocorrect: false,
                decoration: InputDecoration(
                  fillColor: Colors.white,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding:
                      EdgeInsets.only(left: 15, bottom: 11, top: 11, right: 15),
                  hintText: "email address",
                  hintStyle: TextStyle(fontSize: 16, color: AppColors.textMuted),
                  suffixIcon: _codeSent
                      ? TextButton(
                          onPressed: _changeEmail,
                          child: Text('Change',
                              style: TextStyle(color: AppColors.primary)),
                        )
                      : null,
                ),
                style: TextStyle(fontSize: 16, color: AppColors.textMuted),
                keyboardType: TextInputType.emailAddress,
              ),
              margin: EdgeInsets.all(5),
              padding: EdgeInsets.all(5),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(width: 1.0, color: AppColors.surfaceAlt),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        blurRadius: 6.18,
                        spreadRadius: 0.618,
                        offset: Offset(-4, -4),
                        color: Colors.white38),
                    BoxShadow(
                        blurRadius: 6.18,
                        spreadRadius: 0.618,
                        offset: Offset(4, 4),
                        color: Colors.blueGrey.shade100)
                  ]),
            ),
            if (emailIdErrorMessage != '')
              Container(
                child: Text(
                  "\t\t\t\t$emailIdErrorMessage",
                  style: TextStyle(fontSize: 10, color: Colors.red),
                ),
                margin: EdgeInsets.all(2),
                padding: EdgeInsets.all(2),
              ),
            if (_codeSent) ...[
              Container(
                width: double.infinity,
                child: TextFormField(
                  controller: _codeController,
                  autofocus: true,
                  autocorrect: false,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _verifyCode(),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.only(
                        left: 15, bottom: 11, top: 11, right: 15),
                    hintText: "code we emailed you",
                    hintStyle:
                        TextStyle(fontSize: 16, color: AppColors.textMuted),
                  ),
                ),
                margin: EdgeInsets.all(5),
                padding: EdgeInsets.all(5),
                decoration: BoxDecoration(
                    border: Border.all(width: 1.0, color: AppColors.surfaceAlt),
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                          blurRadius: 6.18,
                          spreadRadius: 0.618,
                          offset: Offset(-4, -4),
                          color: Colors.white38),
                      BoxShadow(
                          blurRadius: 6.18,
                          spreadRadius: 0.618,
                          offset: Offset(4, 4),
                          color: Colors.blueGrey.shade100)
                    ]),
              ),
              if (codeErrorMessage != '')
                Container(
                  child: Text(
                    "\t\t\t\t$codeErrorMessage",
                    style: TextStyle(fontSize: 10, color: Colors.red),
                  ),
                  margin: EdgeInsets.all(2),
                  padding: EdgeInsets.all(2),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: (_isSendingCode || _resendCooldown > 0)
                      ? null
                      : _sendCode,
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
            SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (_isSendingCode || _isVerifying)
                    ? null
                    : (_codeSent ? _verifyCode : _sendCode),
                child: (_isSendingCode || _isVerifying)
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : Text(
                        _codeSent ? 'Verify & create account' : 'Send code',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md)),
                ),
              ),
            ),
          ],
        ));
  }

  String? _validateEmailId(String? value) {
    if (value == null || value.isEmpty) {
      setState(() => emailIdErrorMessage = 'you must provide a valid email-id');
    } else if (!validEmailFormat.hasMatch(value)) {
      setState(() =>
          emailIdErrorMessage = 'format of your email address is invalid');
    } else {
      setState(() => emailIdErrorMessage = "");
      emailId = value;
      widget.updateSignUpDetails('emailId', value);
    }

    return null;
  }
}

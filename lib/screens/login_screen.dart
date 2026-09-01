import 'package:flutter/material.dart';
import 'package:dutch_remit/hadwin_components.dart';
import 'package:dutch_remit/utilities/legal_documents.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/components/login_screen/phone_login_form_component.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Phone is the recommended default — real Eversend WhatsApp OTP,
  // zero real money movement, no inbox/spam-folder ambiguity the way
  // email delivery can have. Email remains available as a real
  // alternative for anyone who prefers it.
  bool _usePhone = true;

  @override
  Widget build(BuildContext context) {
    Widget helpInfoContainer = Container(
      child: Center(
        child: InkWell(
          child: Text(
            'Having trouble logging in?',
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
          onTap: getLoginHelp,
        ),
      ),
      width: double.infinity,
      height: 36,
    );

    Widget signUpContainer = Container(
      child: Center(
        child: InkWell(
          onTap: goToSignUpScreen,
          child: RichText(
            text: TextSpan(
              text: "Don't have an account? ",
              style: TextStyle(fontSize: 15, color: AppColors.textMuted),
              children: [
                TextSpan(
                  text: 'Sign up',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
      ),
      width: double.infinity,
      height: 36,
    );

    List<Widget> loginScreenContents = <Widget>[
      _spacing(64),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        child: Center(child: DutchRemitWordmark(fontSize: 30, showTagline: true)),
      ),
      _spacing(48),
      // Two clear, explicit options — phone (real Eversend WhatsApp
      // OTP) is recommended and selected by default; email remains a
      // real, fully-working alternative.
      Row(
        children: [
          Expanded(
            child: _loginMethodTab(
              label: "Phone number",
              sublabel: "Recommended",
              isSelected: _usePhone,
              onTap: () => setState(() => _usePhone = true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _loginMethodTab(
              label: "Email",
              sublabel: null,
              isSelected: !_usePhone,
              onTap: () => setState(() => _usePhone = false),
            ),
          ),
        ],
      ),
      _spacing(20),
      _usePhone ? PhoneLoginFormComponent() : LoginFormComponent(),
      if (!_usePhone) ...[
        _spacing(10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.mark_email_unread_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Don't see the code? Check your spam or junk folder — most of our emails end up there. Mark it \"Not spam\" so future codes arrive in your inbox.",
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
      _spacing(16),
      helpInfoContainer,
      _spacing(10),
      signUpContainer
    ];

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: loginScreenContents,
        ),
        padding: EdgeInsets.all(45),
      
      ),

    
    );
  }

  Widget _loginMethodTab({
    required String label,
    required String? sublabel,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.ink : Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: isSelected ? AppColors.ink : AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : AppColors.ink)),
            if (sublabel != null) ...[
              const SizedBox(height: 2),
              Text(sublabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white.withOpacity(0.75) : AppColors.primary)),
            ],
          ],
        ),
      ),
    );
  }

  void getLoginHelp() {
    Navigator.push(
        context,
        SlideRightRoute(
            page: DutchRemitMarkdownViewer(
                screenName: 'Login Help',
                content: kLoginHelp)));
  }

  void goToSignUpScreen() {
    Navigator.push(
        context, MaterialPageRoute(builder: (context) => SignUpScreen()));
  }

  SizedBox _spacing(double height) => SizedBox(
        height: height,
      );
}


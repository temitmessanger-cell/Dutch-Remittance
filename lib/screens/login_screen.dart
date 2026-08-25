import 'package:flutter/material.dart';
import 'package:dutch_remit/hadwin_components.dart';
import 'package:dutch_remit/database/hadwin_user_device_info_storage.dart';
import 'package:dutch_remit/screens/onboarding_screen.dart';
import 'package:dutch_remit/components/main_app_screen/tabbed_layout_component.dart';
import 'package:dutch_remit/utilities/legal_documents.dart';
import 'package:dutch_remit/utilities/app_theme.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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

    Widget continueAsGuestContainer = Container(
      margin: EdgeInsets.symmetric(vertical: 6),
      width: double.infinity,
      child: OutlinedButton(
        onPressed: continueAsGuest,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(vertical: 16),
          side: BorderSide(color: AppColors.primary, width: 1.6),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md)),
        ),
        child: Text(
          'Continue as Guest',
          style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primary),
        ),
      ),
    );

    List<Widget> loginScreenContents = <Widget>[
      _spacing(64),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        child: Center(child: DutchRemitWordmark(fontSize: 30, showTagline: true)),
      ),
      _spacing(64),
      LoginFormComponent(),
      _spacing(16),
      continueAsGuestContainer,
      _spacing(14),
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

  void continueAsGuest() async {
    // A guest who already saw onboarding once (e.g. they backed out and
    // returned to this screen) shouldn't see it again — go straight to
    // the main app, with no logged-in user data.
    final alreadyOnboarded = await UserDeviceInfoStorage().wasUsedBefore;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (context) => alreadyOnboarded
                ? TabbedLayoutComponent(userData: const {})
                : OnboardingScreen()),
        (route) => false);
  }

  SizedBox _spacing(double height) => SizedBox(
        height: height,
      );
}


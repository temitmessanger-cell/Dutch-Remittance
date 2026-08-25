import 'package:flutter/material.dart';
import 'package:dutch_remit/hadwin_components.dart';
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

    List<Widget> loginScreenContents = <Widget>[
      _spacing(64),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        child: Center(child: DutchRemitWordmark(fontSize: 30, showTagline: true)),
      ),
      _spacing(64),
      LoginFormComponent(),
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


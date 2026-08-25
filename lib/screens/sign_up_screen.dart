import 'package:flutter/material.dart';
import 'package:dutch_remit/hadwin_components.dart';
import 'package:dutch_remit/utilities/app_theme.dart';



class SignUpScreen extends StatefulWidget {
  const SignUpScreen({Key? key}) : super(key: key);

  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        child: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                SizedBox(
                  height: 16,
                ),
                Container(
                  child: Center(child: DutchRemitWordmark(fontSize: 22)),
                  height: 30,
                ),
                SizedBox(
                  height: 30,
                ),
               
                SignUpSteps(),
                SizedBox(
                  height: 27,
                ),

                Container(
                  child: Center(
                    child: InkWell(
                      child: Text(
                        'Already have an account? Sign in',
                        style:
                            TextStyle(fontSize: 14, color: AppColors.textMuted),
                      ),
                      onTap: () {
                      
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  width: double.infinity,
                  height: 16,
                ),
                SizedBox(
                  height: 3,
                )
              ],
            ),
            padding: EdgeInsets.all(45),
         
          ),

        ),
        onWillPop: () => Future.value(false));
  }
}


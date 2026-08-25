import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:dutch_remit/components/sign_up_screen/choose_username_screen.dart';
import 'package:dutch_remit/components/sign_up_screen/step_get_email_otp.dart';
import 'package:dutch_remit/components/sign_up_screen/step_get_name_address.dart';
import 'package:dutch_remit/utilities/hadwin_markdown_viewer.dart';
import 'package:dutch_remit/utilities/legal_documents.dart';

import 'package:dutch_remit/utilities/slide_right_route.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

class SignUpSteps extends StatefulWidget {
  const SignUpSteps({Key? key}) : super(key: key);

  @override
  _SignUpStepsState createState() => _SignUpStepsState();
}

class _SignUpStepsState extends State<SignUpSteps> {
  late PageController _signUpStepController;
  final nameAddressFormKey = LabeledGlobalKey<FormState>("nameAddressForm");
  final emailOtpFormKey = LabeledGlobalKey<FormState>("emailOtpForm");
  Map<String, String> signUpDetails = {
    'fullname': '',
    'address': '',
    'emailId': '',
  };
  Map<String, String> registraionDetails() => signUpDetails;
  int _currentStep = 0;
  List<bool> stepHasError = [false, false];
  List<bool> stepCompletedSuccessfully = [false, false];
  late List<Widget> signUpStepContent;
  @override
  void initState() {
    _signUpStepController = PageController();
    signUpStepContent = [
      StepGetNameAddress(
        registrationDetails: registraionDetails,
        updateSignUpDetails: updateSignUpDetails,
        nameAddressFormKey: nameAddressFormKey,
        proceedToNextStep: _proceedToNextStep,
      ),
      StepGetEmailOtp(
        updateSignUpDetails: updateSignUpDetails,
        emailOtpFormKey: emailOtpFormKey,
        registrationDetails: registraionDetails,
        onAccountCreated: _onAccountCreated,
      ),
    ];

    super.initState();
  }

  @override
  void dispose() {
    _signUpStepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        width: double.infinity,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [0, 1]
                    .map((e) => Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () => changeStepOnTap(e),
                              child: CircleAvatar(
                                  backgroundColor: stepHasError[e]
                                      ? Colors.red.shade600
                                      : !stepCompletedSuccessfully[e]
                                          ? AppColors.surfaceAlt
                                          : Colors.green.shade600,
                                  foregroundColor: !stepCompletedSuccessfully[e]
                                      ? AppColors.primary
                                      : Colors.white,
                                  radius: 18,
                                  child: stepHasError[e]
                                      ? Icon(
                                          FluentIcons.warning_16_filled,
                                          color: Colors.white,
                                        )
                                      : stepCompletedSuccessfully[e]
                                          ? Icon(
                                              FluentIcons.checkmark_16_regular)
                                          : _currentStep == e
                                              ? Icon(FluentIcons.edit_16_filled)
                                              : Text("${e + 1}")),
                            ),
                            if (e < 1)
                              Container(
                                height: 10,
                                width: 70,
                                color: stepCompletedSuccessfully[e]
                                    ? Colors.green.shade600
                                    : Colors.transparent,
                              ),
                          ],
                        ))
                    .toList(),
              ),
            ),
            SizedBox(
              height: 50,
            ),
            Container(
              width: double.infinity,
              height: _currentStep == 1 ? 380 : 300,
              child: PageView(
                clipBehavior: Clip.none,
                controller: _signUpStepController,
                physics: NeverScrollableScrollPhysics(),
                children: signUpStepContent,
              ),
            ),
            if (_currentStep == 1)
              Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 3.6, horizontal: 10),
                  child: RichText(
                      text: TextSpan(
                          text: 'By signing up you are agreeing to the ',
                          style: TextStyle(
                              fontSize: 14, color: AppColors.textMuted),
                          children: <InlineSpan>[
                        TextSpan(
                            text: 'Terms & Conditions',
                            style: TextStyle(fontSize: 14, color: Colors.blue),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                FocusManager.instance.primaryFocus?.unfocus();
                                Future.delayed(
                                    Duration(milliseconds: 300),
                                    () => Navigator.push(
                                        context,
                                        SlideRightRoute(
                                            page: DutchRemitMarkdownViewer(
                                          screenName: "Terms & Conditions",
                                          content: kTermsOfUse,
                                        ))));
                              }),
                        TextSpan(
                          text: ' and our ',
                          style: TextStyle(
                              fontSize: 14, color: AppColors.textMuted),
                        ),
                        TextSpan(
                            text: 'End User License Agreement',
                            style: TextStyle(fontSize: 14, color: Colors.blue),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                FocusManager.instance.primaryFocus?.unfocus();
                                Future.delayed(
                                    Duration(milliseconds: 300),
                                    () => Navigator.push(
                                        context,
                                        SlideRightRoute(
                                            page: DutchRemitMarkdownViewer(
                                          screenName:
                                              "End User License Agreement",
                                          content: kEndUserLicenseAgreement,
                                        ))));
                              })
                      ]))),
            if (_currentStep == 0)
              Row(
                children: [
                  Spacer(),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextButton(
                        onPressed: _proceedToNextStep,
                        child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 3.2,
                            children: [
                              Text(
                                'Next',
                                style:
                                    TextStyle(color: Colors.blue, fontSize: 16),
                              ),
                              Icon(
                                FluentIcons.arrow_right_16_filled,
                                color: Colors.blue,
                                size: 18,
                              )
                            ]),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        )),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextButton(
                        onPressed: _goBackToPreviousStep,
                        child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 3.2,
                            children: [
                              Icon(
                                FluentIcons.arrow_left_16_filled,
                                color: Colors.blue,
                                size: 18,
                              ),
                              Text(
                                'Back',
                                style:
                                    TextStyle(color: Colors.blue, fontSize: 16),
                              ),
                            ]),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        )),
                  ),
                ],
              ),
          ],
        ));
  }

//? FUNCTION TO GO BACK TO PREVIOUS STEP OF THE CURRENT STEP
  void _goBackToPreviousStep() {
    FocusManager.instance.primaryFocus?.unfocus();
    _performErrorCheck(_currentStep - 1);
    if (_currentStep > 0) {
      _signUpStepController.animateToPage(_currentStep - 1,
          duration: Duration(milliseconds: 500), curve: Curves.easeInOutCubic);
      setState(() {
        _currentStep--;
      });
    }
  }

//? FUNCTION TO MOVE TO THE NEXT STEP FROM THE CURRENT STEP
  void _proceedToNextStep() {
    FocusManager.instance.primaryFocus?.unfocus();

    _performErrorCheck(_currentStep + 1);

    if (stepHasError[_currentStep] == false) {
      if (_currentStep < signUpStepContent.length - 1) {
        _signUpStepController.animateToPage(_currentStep + 1,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic);

        setState(() {
          _currentStep++;
        });
      }
    }
  }

//? FUNCTION TO UPDATE SIGN UP DETAILS
  void updateSignUpDetails(String key, String value) {
    setState(() {
      signUpDetails[key] = value;
    });
  }

  // Called by StepGetEmailOtp once the emailed code has been verified
  // and the backend has returned a real Supabase session + profile —
  // the account already exists at this point, so this just routes on,
  // exactly like the old password-based flow's post-registration step.
  void _onAccountCreated(Map<String, dynamic> response) {
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (context) => ChooseUsername(
                  userAuthKey: response['authorization_token'],
                  userData: response['user'],
                )),
        (route) => false);
  }

//? FUNCTION TO CHECK FOR ERRORS IN ANY STEPS PRIOR FROM THE ONE REQUESTED
  void _performErrorCheck(int requestedIndex) {
    if (_currentStep < requestedIndex) {
      for (var i = 0; i < requestedIndex; i++) {
        bool errorStatus = false;
        switch (i) {
          case 0:
            nameAddressFormKey.currentState?.validate();
            if (signUpDetails["fullname"]!.isEmpty ||
                signUpDetails['address']!.isEmpty) {
              errorStatus = true;
            }

            break;
          case 1:
            if (signUpDetails["emailId"]!.isEmpty) {
              errorStatus = true;
            }
            break;
        }

        setState(() {
          stepHasError[i] = errorStatus;
          stepCompletedSuccessfully[i] = !stepHasError[i];
        });
        if (errorStatus) {
          break;
        }
      }
    } else {
      for (var i = _currentStep; i >= 0; i--) {
        bool errorStatus = false;
        switch (i) {
          case 0:
            nameAddressFormKey.currentState?.validate();
            if (signUpDetails["fullname"]!.isEmpty ||
                signUpDetails['address']!.isEmpty) {
              errorStatus = true;
            }

            break;
          case 1:
            if (signUpDetails["emailId"]!.isEmpty) {
              errorStatus = true;
            }
            break;
        }

        setState(() {
          stepHasError[i] = errorStatus;
          stepCompletedSuccessfully[i] = !stepHasError[i];
        });
        if (errorStatus) {
          break;
        }
      }
    }
  }

//? FUNCTION TO CHANGE STEP ON TAPPING THE OVERHEAD STEP NUMBERS
  void changeStepOnTap(int requestedIndex) {
    FocusManager.instance.primaryFocus?.unfocus();

    if (requestedIndex < _currentStep) {
      _signUpStepController.animateToPage(requestedIndex,
          duration: Duration(milliseconds: 500), curve: Curves.easeInOutCubic);

      _performErrorCheck(requestedIndex);
      setState(() {
        _currentStep = requestedIndex;
      });
    } else if (requestedIndex > _currentStep &&
        requestedIndex != _currentStep) {
      _performErrorCheck(requestedIndex);

      if (!stepHasError.sublist(0, requestedIndex).contains(true)) {
        if (_currentStep < signUpStepContent.length - 1) {
          _signUpStepController.animateToPage(requestedIndex,
              duration: Duration(milliseconds: 500),
              curve: Curves.easeInOutCubic);

          setState(() {
            _currentStep = requestedIndex;
          });
        }
      } else {
        int stepWithError =
            stepHasError.sublist(0, requestedIndex).indexOf(true);
        _signUpStepController.animateToPage(stepWithError,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic);

        setState(() {
          _currentStep = stepWithError;
        });
      }
    }
  }
}

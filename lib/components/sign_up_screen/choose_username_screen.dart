import 'dart:async';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:dutch_remit/components/main_app_screen/tabbed_layout_component.dart';
import 'package:dutch_remit/database/hadwin_user_device_info_storage.dart';
import 'package:dutch_remit/database/login_info_storage.dart';
import 'package:dutch_remit/database/user_data_storage.dart';
import 'package:dutch_remit/screens/onboarding_screen.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/hadwin_components.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';

/// The final sign-up step: pick a username. This used to check
/// availability over a live Socket.IO connection to the old custom
/// backend ("username request"/"username status" events) — that
/// backend is gone, so this now debounces a plain REST call to
/// GET /api/v1/auth/check-username, and persists the chosen username
/// server-side via POST /api/v1/auth/set-username (previously the
/// username was only ever saved to local device storage, never
/// actually reserved anywhere — nothing stopped two people from
/// picking the same one).
class ChooseUsername extends StatefulWidget {
  final String userAuthKey;
  final Map<String, dynamic> userData;
  const ChooseUsername(
      {Key? key, required this.userAuthKey, required this.userData})
      : super(key: key);

  @override
  _ChooseUsernameState createState() => _ChooseUsernameState();
}

class _ChooseUsernameState extends State<ChooseUsername> {
  LoginInfoStorage loginInfoStorage = LoginInfoStorage();
  UserDataStorage userDataStorage = UserDataStorage();
  late TextEditingController usernameField;
  bool usernameStatus = false;
  bool _isChecking = false;
  bool _isSaving = false;
  Timer? _debounce;
  bool _showErrorMessage = false;
  String _message = "your account has been created\nchoose a username";

  @override
  void initState() {
    super.initState();
    usernameField = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    usernameField.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    setState(() {
      if (_showErrorMessage) _showErrorMessage = false;
      usernameStatus = false;
    });
    _debounce?.cancel();
    if (value.trim().length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 400), () => _checkAvailability(value.trim()));
  }

  Future<void> _checkAvailability(String username) async {
    setState(() => _isChecking = true);
    final result = await getData(
        urlPath: "/api/v1/auth/check-username?username=${Uri.encodeQueryComponent(username)}");
    if (!mounted || usernameField.text.trim() != username) return;
    setState(() {
      _isChecking = false;
      usernameStatus = result['available'] == true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 64,
            ),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blueGrey.shade100,
                  radius: 64,
                  child: ClipOval(
                    child: (widget.userData['gender'] != null && widget.userData['avatar'] != null)
                        ? Image.network(
                            "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/Dutch Remit_users/${widget.userData['gender']?.toString().toLowerCase() ?? ''}/${widget.userData['avatar']}",
                            height: 120,
                            width: 120,
                            fit: BoxFit.cover,
                            // No avatar-hosting is wired up on the new
                            // backend yet — this step wasn't producing a
                            // real gender/avatar selection anywhere
                            // upstream in the sign-up flow to begin with,
                            // so fall back to a simple placeholder rather
                            // than show Flutter's broken-image icon.
                            errorBuilder: (context, error, stackTrace) =>
                                Icon(Icons.person_rounded, size: 64, color: AppColors.textMuted),
                          )
                        : Icon(Icons.person_rounded, size: 64, color: AppColors.textMuted),
                  ),
                )
              ],
              mainAxisAlignment: MainAxisAlignment.center,
            ),
            Container(
              height: 48,
              margin: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _showErrorMessage ? 'the username is not available' : _message,
                style: TextStyle(
                    color:
                        _showErrorMessage ? Colors.red : Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
            ),
            Container(
              width: 260,
              child: TextField(
                controller: usernameField,
                onChanged: _onUsernameChanged,
                decoration: InputDecoration(
                  suffixIcon: usernameField.text.isEmpty
                      ? null
                      : _isChecking
                          ? Padding(
                              padding: const EdgeInsets.all(14),
                              child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: usernameStatus == true
                                    ? Colors.green
                                    : Colors.red,
                                borderRadius: BorderRadius.only(
                                    topRight: Radius.circular(16),
                                    bottomRight: Radius.circular(16)),
                              ),
                              child: Icon(
                                usernameStatus == true
                                    ? FluentIcons.checkmark_48_regular
                                    : FluentIcons.prohibited_48_regular,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                  fillColor: Colors.white,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding:
                      EdgeInsets.only(left: 15, bottom: 11, top: 11, right: 15),
                  hintText: "username",
                  hintStyle: TextStyle(fontSize: 16, color: AppColors.textMuted),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => trySettingUsername(),
                style: TextStyle(fontSize: 16, color: AppColors.textMuted),
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
            SizedBox(
              height: 18,
            ),
            Container(
              width: 270,
              height: 64,
              margin: const EdgeInsets.all(5.0),
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                      color: Colors.blueGrey.shade100,
                      offset: Offset(0, 4),
                      blurRadius: 5.0)
                ],
                gradient: RadialGradient(
                    colors: [AppColors.primary, AppColors.primary],
                    radius: 8.4,
                    center: Alignment(-0.24, -0.36)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: ElevatedButton(
                  onPressed: _isSaving ? null : trySettingUsername,
                  child: _isSaving
                      ? SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Confirm'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  )),
            ),
          ],
        ),
        padding: EdgeInsets.all(45),
      ),
    );
  }

  void trySettingUsername() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (usernameField.text.trim().isNotEmpty && usernameStatus == true) {
      setState(() => _isSaving = true);

      final result = await sendData(
        urlPath: "/api/v1/auth/set-username",
        data: {"username": usernameField.text.trim()},
        authKey: widget.userAuthKey,
      );

      if (!mounted) return;

      if (result.containsKey('error') || result.containsKey('apiRequestError')) {
        setState(() {
          _isSaving = false;
          _showErrorMessage = true;
          usernameStatus = false;
        });
        return;
      }

      Map<String, dynamic> data = {
        ...widget.userData,
        'username': usernameField.text.trim(),
      };
      final status = await Future.wait([
        _saveLoggedInUserData(widget.userAuthKey, data),
        CardsStorage().initializeAvailableCards(widget.userAuthKey),
        SuccessfulTransactionsStorage().initializeSuccessfulTransactions()
      ]);

      if (!mounted) return;
      setState(() => _isSaving = false);

      if (status[0] == true && status[1] == true && status[2] == true) {
        final alreadyOnboarded = await UserDeviceInfoStorage().wasUsedBefore;

        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(
                content: Text("Successfully created account"),
                backgroundColor: AppColors.success))
            .closed
            .then((value) => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (context) => alreadyOnboarded
                        ? TabbedLayoutComponent(userData: data)
                        : OnboardingScreen(userData: data)),
                (route) => false));
      }
    } else {
      setState(() {
        _showErrorMessage = true;
      });
    }
  }

  Future<bool> _saveLoggedInUserData(
      String loggedInUserAuthKey, Map<String, dynamic> user) async {
    try {
      Provider.of<UserLoginStateProvider>(context, listen: false)
          .setAuthKeyValue(loggedInUserAuthKey);

      final userIsSaved = await Future.wait([
        userDataStorage.saveUserData(user),
        loginInfoStorage.setPersistentLoginData(
            user['id'].toString(), loggedInUserAuthKey)
      ]);
      Provider.of<UserLoginStateProvider>(context, listen: false)
          .initializeBankBalance(user);
      //* user data saved

      if (userIsSaved[0] && userIsSaved[1]) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }
}

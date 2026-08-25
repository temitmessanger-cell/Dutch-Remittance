import 'package:flutter/material.dart';
import 'package:dutch_remit/database/login_info_storage.dart';
import 'package:dutch_remit/database/user_data_storage.dart';

import 'package:dutch_remit/screens/login_screen.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

Future<bool> _deleteLoggedInUserData() async {
  List<bool> deletionStatus = await Future.wait(
      [LoginInfoStorage().deleteFile(), UserDataStorage().deleteFile()]);
  return deletionStatus.first && deletionStatus.last;
}

void showErrorAlert(BuildContext context, Map<String, dynamic> error) {
  Map<String, dynamic> errorTypes = {
    'error': _CommonError(context, error),
    'internetConnectionError': _LocalError(context, error),
    'localDBError': _LocalError(context, error),
    'authenticationError': _CommonError(context, error),
    'apiAuthorizationError': _HazardousError(context, error),
    'corruptedTokenError': _HazardousError(context, error),
    // getData()/sendData() in make_api_request.dart return this key on
    // every network failure (timeout, CORS rejection, non-2xx status,
    // bad JSON, etc.) — without it registered here, any backend hiccup
    // crashed the whole screen with a NoSuchMethodError on null, since
    // errorTypes[currentError] would resolve to null.
    'apiRequestError': _LocalError(context, error),
  };
  String currentError = error.keys.first;

  // Defensive fallback: if some future error shape introduces a key not
  // covered above, fall back to a generic message instead of crashing —
  // an unrecognized error key should never take down the whole UI.
  final errorHandler = errorTypes[currentError] ??
      _CommonError(context, {'error': 'Something went wrong. Please try again.'});

  showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
            title: Text(
              "Error",
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: errorHandler.errorDescription,
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              Container(
                height: 48,
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
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ElevatedButton(
                    onPressed: errorHandler.onClose,
                    child: Text('OK'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    )),
              )
            ],
          ));
}

class _CommonError {
  BuildContext context;
  Map<String, dynamic> error;
  _CommonError(this.context, this.error);
  List<Widget> get errorDescription => <Widget>[
        Padding(
          padding: EdgeInsets.only(top: 24, bottom: 12),
          child: Text(
            error[error.keys.first],
            textAlign: TextAlign.center,
          ),
        ),
      ];

  void onClose() {
    Navigator.of(context).pop();
  }
}

class _LocalError {
  BuildContext context;
  Map<String, dynamic> error;
  _LocalError(this.context, this.error);

  List<Widget> get errorDescription => <Widget>[
        error.keys.first == 'internetConnectionError'
            ? ColorFiltered(
                colorFilter:
                    ColorFilter.mode(AppColors.primary, BlendMode.color),
                child: ColorFiltered(
                  colorFilter:
                      ColorFilter.mode(Colors.grey, BlendMode.saturation),
                  child: Image.asset(
                    'assets/images/notification_assets/no-wifi.png',
                    height: 48,
                    width: 48,
                  ),
                ))
            : Image.asset(
                'assets/images/notification_assets/file-error.png',
                height: 48,
                width: 48,
              ),
        Padding(
          padding: EdgeInsets.only(top: 24, bottom: 12),
          child: Text(
            error[error.keys.first],
            textAlign: TextAlign.center,
          ),
        ),
      ];

  void onClose() {
    Navigator.of(context).pop();
  }
}

class _HazardousError {
  BuildContext context;
  Map<String, dynamic> error;
  _HazardousError(this.context, this.error);
  List<Widget> get errorDescription => <Widget>[
        Padding(
          padding: EdgeInsets.only(top: 24, bottom: 12),
          child: Text(
            error[error.keys.first],
            textAlign: TextAlign.center,
          ),
        ),
      ];

  void onClose() async {
    final logOutStatus = await _deleteLoggedInUserData();
    if (logOutStatus) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => LoginScreen()),
          (route) => false);
    }
  }
}



import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/components/main_app_screen/local_splash_screen_component.dart';

import 'package:dutch_remit/screens/onboarding_screen.dart';
import 'package:dutch_remit/database/cards_storage.dart';
import 'package:dutch_remit/database/contacts_storage.dart';
import 'package:dutch_remit/database/currency_conversion_service.dart';
import 'package:dutch_remit/database/login_info_storage.dart';
import 'package:dutch_remit/database/hadwin_user_device_info_storage.dart';
import 'package:dutch_remit/database/product_tour_storage.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/database/user_data_storage.dart';
import 'package:dutch_remit/providers/live_transactions_provider.dart';
import 'package:dutch_remit/providers/tab_navigation_provider.dart';

import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';

import 'package:provider/provider.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Hive works identically across mobile, desktop, and web (unlike the
  // dart:io File-based storage this app used before), so every box is
  // opened up front, here, exactly once.
  await Hive.initFlutter();
  await Future.wait([
    Hive.openBox(CardsStorage.boxName),
    Hive.openBox(ContactsStorage.boxName),
    Hive.openBox(UserDataStorage.boxName),
    Hive.openBox(LoginInfoStorage.boxName),
    Hive.openBox(SuccessfulTransactionsStorage.boxName),
    Hive.openBox(UserDeviceInfoStorage.boxName),
    Hive.openBox(CurrencyConversionService.boxName),
    Hive.openBox(ProductTourStorage.boxName),
  ]);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => UserLoginStateProvider(),
      ),
      ChangeNotifierProxyProvider<UserLoginStateProvider,
              LiveTransactionsProvider>(
          create: (BuildContext context) => LiveTransactionsProvider(),
          update: (context, userLoginAuthKey, liveTransactions) =>
              liveTransactions!..update(userLoginAuthKey)),
      ChangeNotifierProvider(create: (_) => TabNavigationProvider()),
    ],
    child: MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  UserDeviceInfoStorage userDeviceInfoStorage = UserDeviceInfoStorage();
  UserDataStorage userDataStorage = UserDataStorage();
  LoginInfoStorage loginInfoStorage = LoginInfoStorage();
  bool? _previousllyInstalled = null;
  bool? _isLoggedIn = null;
  Map<String, dynamic>? _loggedInUserData = null;

  void _checkForPreviousInstallations() async {
    final previousllyInstalledStatus =
        await userDeviceInfoStorage.wasUsedBefore;
    setState(() {
      _previousllyInstalled = previousllyInstalledStatus;
    });
  }

  void _getLoggedInUserData() async {
    final loginData = await loginInfoStorage.getPersistentLoginData;
    final loggedInUserAuthKey = loginData['authToken'];
    final loggedInUserId = loginData['userId'];
    bool loginStatus;
    if (loggedInUserAuthKey == null || loggedInUserId == null) {
      loginStatus = false;
    } else {
      Provider.of<UserLoginStateProvider>(context, listen: false)
          .setAuthKeyValue(loggedInUserAuthKey);

      await CardsStorage().initializeAvailableCards(loggedInUserAuthKey);
      await SuccessfulTransactionsStorage().initializeSuccessfulTransactions();

      final userValidity =
          await fetchUserId(loggedInUserAuthKey, loggedInUserId);
      //* user data saved

      loginStatus = userValidity;
    }
    setState(() {
      _isLoggedIn = loginStatus;
    });
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }

    _checkForPreviousInstallations();

    _getLoggedInUserData();
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Dutch Remit',
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) {
            // Still resolving Hive/login state — show the splash screen
            // and wait. This must be checked first, before any routing
            // decision, or the UI flashes the wrong screen for a frame.
            if (_previousllyInstalled == null || _isLoggedIn == null) {
              return Material(
                type: MaterialType.transparency,
                child: LocalSplashScreenComponent(),
              );
            }

            _safeRemoveSplash();

            // A returning user who has already completed onboarding
            // before: still show the onboarding screen first — it's
            // now the app's permanent entry point for everyone — but
            // carry their session through so "Start sending" drops
            // them straight back into the app instead of asking them
            // to log in again.
            if (_previousllyInstalled == true) {
              if (_isLoggedIn == true && _loggedInUserData != null) {
                return OnboardingScreen(userData: _loggedInUserData!);
              }
              return OnboardingScreen();
            }

            // First-ever launch: onboarding shows first, exactly the
            // same as for returning users above.
            return OnboardingScreen();
          },
        ),
        debugShowCheckedModeBanner: false);
  }

  void _safeRemoveSplash() {
    try {
      FlutterNativeSplash.remove();
    } catch (_) {
      // ignore: intentionally swallow splash removal errors on web or if not generated
    }
  }

  Future<bool> fetchUserId(String authKey, String userId) async {
    final dataReceived =
        await getData(urlPath: "/Dutch Remit/v3/user/$userId", authKey: authKey);
    if (dataReceived.keys.join().toLowerCase().contains("error")) {
      return false;
    } else {
      bool userIsSaved =
          await UserDataStorage().saveUserData(dataReceived['user']);
      Provider.of<UserLoginStateProvider>(context, listen: false)
          .initializeBankBalance(dataReceived['user']);

      if (userIsSaved) {
        //? in case user is valid
        if (mounted) {
          setState(() {
            _loggedInUserData = dataReceived['user'];
          });
        }
      }

      return userIsSaved;
    }
  }
}


import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/components/main_app_screen/local_splash_screen_component.dart';

import 'package:dutch_remit/screens/onboarding_screen.dart';
import 'package:dutch_remit/database/cards_storage.dart';
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

Future<Box> _openUserDataBox() async {
  try {
    return await Hive.openBox(UserDataStorage.boxName);
  } catch (_) {
    // Recover from a stale Hive web object store created by an older build.
    try {
      await Hive.deleteBoxFromDisk(UserDataStorage.boxName);
    } catch (_) {}
    return Hive.openBox(UserDataStorage.boxName);
  }
}

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Hive.initFlutter();

  // One-time cleanup of the device-global boxes that used to cache
  // per-user business data (transactions, contacts, cards). These
  // leaked one user's data into the next user's session on a shared
  // browser/device. Those stores are now backend-only (see their
  // storage classes), so we actively DELETE any stale box left on a
  // returning user's device here — this is what clears the "phantom"
  // transactions/contacts/cards a user reported seeing that weren't
  // theirs. Wrapped so a missing box is never fatal.
  for (final staleBox in <String>[
    'dutch_remit_successful_transactions',
    'dutch_remit_local_contacts',
    'dutch_remit_available_cards',
  ]) {
    try {
      await Hive.deleteBoxFromDisk(staleBox);
    } catch (_) {}
  }

  // Remaining boxes are legitimately device-local (login session,
  // device info, FX cache, product-tour-seen flag) and are opened
  // once here. None of them hold another user's business data.
  await Future.wait([
    _openUserDataBox(),
    Hive.openBox(LoginInfoStorage.boxName),
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


import 'dart:async';
import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

import 'package:dutch_remit/providers/live_transactions_provider.dart';
import 'package:dutch_remit/providers/tab_navigation_provider.dart';

import 'package:dutch_remit/providers/user_login_state_provider.dart';

import 'package:dutch_remit/components/main_app_screen/product_tour_overlay.dart';
import 'package:dutch_remit/database/product_tour_storage.dart';

import 'package:dutch_remit/screens/send_tab_hub_screen.dart';
import 'package:dutch_remit/screens/all_transaction_activities_screen.dart';
import 'package:dutch_remit/screens/profile_settings_tab_screen.dart';
import 'package:dutch_remit/screens/send_abroad_hub_screen.dart';

import 'package:dutch_remit/screens/home_dashboard_screen.dart';

import 'package:dutch_remit/screens/wallet_screen.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

import 'package:provider/provider.dart';

class TabbedLayoutComponent extends StatefulWidget {
  final Map<String, dynamic> userData;
  const TabbedLayoutComponent({Key? key, required this.userData})
      : super(key: key);
  @override
  _TabbedLayoutComponentState createState() =>
      new _TabbedLayoutComponentState();
}

class _TabbedLayoutComponentState extends State<TabbedLayoutComponent> {

  Timer? _updateTransactionsTimer;
  int _currentTab = 0;
  int totalTransactionRequests = 0;

  final LabeledGlobalKey<HomeDashboardScreenState> dashboardScreenKey =
      LabeledGlobalKey("Dashboard Screen");
  final LabeledGlobalKey<AllTransactionActivitiesState>
      transactionActivitiesScreenKey =
      LabeledGlobalKey("Transaction Activities Screen");

  // Guided product tour — a single key on the nav bar's container lets
  // the overlay compute each tab's on-screen position by dividing its
  // width evenly (GNav lays its tabs out with equal spacing), which is
  // far more robust than reaching into GNav's internals per-tab.
  final GlobalKey _navBarKey = GlobalKey();
  bool _showTour = false;
  final ProductTourStorage _tourStorage = ProductTourStorage();

  static final List<TourStep> _tourSteps = [
    TourStep(
      tabIndex: 0,
      icon: Icons.home_rounded,
      title: "Your Home",
      description:
          "See your live balance, contacts, and latest transactions at a glance.",
    ),
    TourStep(
      tabIndex: 1,
      icon: Icons.public_rounded,
      title: "Send Abroad",
      description:
          "Send money internationally with real, live exchange rates — pick any currency and see exactly what arrives.",
    ),
    TourStep(
      tabIndex: 2,
      icon: Icons.credit_card_rounded,
      title: "Card",
      description:
          "Manage your saved cards, view card details, and add new ones securely.",
    ),
    TourStep(
      tabIndex: 3,
      icon: Icons.people_rounded,
      title: "Send",
      description:
          "Pick a contact or business to pay or request money from, and manage your saved recipients.",
    ),
    TourStep(
      tabIndex: 4,
      icon: Icons.receipt_long_rounded,
      title: "Payments",
      description:
          "A complete, filterable history of every payment sent and received — always one tap away.",
    ),
    TourStep(
      tabIndex: 5,
      icon: Icons.person_outline_rounded,
      title: "Profile",
      description:
          "Manage your account, linked banks, and app settings — all in one place.",
    ),
  ];

  @override
  void initState() {
    super.initState();

    _updateTransactionsTimer = Timer.periodic(
        Duration(minutes: [1, 2, 3, 4][Random().nextInt(4)]), (Timer t) {
      Provider.of<LiveTransactionsProvider>(context, listen: false)
          .updateTransactionRequests();
     
    });

    _maybeShowTourOnFirstLaunch();
    ProductTourStorage.replayRequested.addListener(_onTourReplayRequested);
  }

  void _onTourReplayRequested() {
    if (mounted) startTour();
  }

  void _maybeShowTourOnFirstLaunch() async {
    final seen = await _tourStorage.hasSeenTour;
    if (!seen && mounted) {
      // Let the first frame (and nav bar layout) settle before spotlighting.
      WidgetsBinding.instance!.addPostFrameCallback((_) {
        if (mounted) setState(() => _showTour = true);
      });
    }
  }

  /// Replays the guided tour on demand (e.g. from Settings), regardless
  /// of whether it has been seen before.
  void startTour() {
    setState(() {
      _currentTab = 0;
      _showTour = true;
    });
  }

  void _finishTour() {
    _tourStorage.markTourSeen();
    setState(() => _showTour = false);
  }

  @override
  void dispose() {
    _updateTransactionsTimer!.cancel();
    ProductTourStorage.replayRequested.removeListener(_onTourReplayRequested);
    super.dispose();
  }

  void setTab(int index) {
    setState(() {
      _currentTab = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    String userAuthKey =
        Provider.of<UserLoginStateProvider>(context).userLoginAuthKey;

    List<Widget> screens = [
      HomeDashboardScreen(
        user: widget.userData,
        userAuthKey: userAuthKey,
        setTab: setTab,
        key: dashboardScreenKey,
      ),
      SendAbroadHubScreen(
        user: widget.userData,
        userAuthKey: userAuthKey,
      ),
      WalletScreen(
        setTab: setTab,
        user: widget.userData,
        userAuthKey: userAuthKey,
      ),
      SendTabHubScreen(
        userAuthKey: userAuthKey,
        setTab: setTab,
        user: widget.userData,
      ),
      AllTransactionActivities(
        user: widget.userData,
        userAuthKey: userAuthKey,
        setTab: setTab,
        key: transactionActivitiesScreenKey,
      ),
      ProfileSettingsTabScreen(
        user: widget.userData,
      ),
    ];
    return WillPopScope(
      onWillPop: _onBackPress,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: AppColors.scaffold,

            extendBodyBehindAppBar: true,

            bottomNavigationBar: googleNavBar(),

            body: screens.isEmpty
                ? Text("Loading...")
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_currentTab),
                      child: screens[_currentTab],
                    ),
                  ),
          ),
          if (_showTour)
            Positioned.fill(
              child: ProductTourOverlay(
                steps: _tourSteps,
                navBarKey: _navBarKey,
                tabCount: 6,
                onStepChanged: (tabIndex) => setTab(tabIndex),
                onFinished: _finishTour,
              ),
            ),
        ],
      ),
    );
  }

  Widget googleNavBar() {
    int unreadTransactions =
        context.watch<LiveTransactionsProvider>().unreadTransactions;
    int transactionRequests =
        context.watch<LiveTransactionsProvider>().transactionRequests;
    if (transactionRequests != totalTransactionRequests) {
      setState(() {
        totalTransactionRequests = transactionRequests;
      });
      if (_currentTab == 0) {
        dashboardScreenKey.currentState!.getTransactionsFromApi();
      } else if (_currentTab == 4) {
        transactionActivitiesScreenKey.currentState!.getTransactionsFromApi();
      }
    }

    return Container(
      key: _navBarKey,
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: GNav(
            haptic: false,
            gap: 4,
            activeColor: AppColors.primary,
            tabBackgroundColor: AppColors.primary.withOpacity(0.08),
            iconSize: 22,
            tabMargin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            duration: Duration(milliseconds: 300),
            color: AppColors.textMuted,
            textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                fontFamily: 'Manrope'),
            tabs: [
              GButton(
                icon: FluentIcons.home_32_regular,
                iconSize: 24,
                text: 'Home',
              ),
              GButton(
                icon: Icons.public_rounded,
                iconSize: 22,
                text: 'Send Abroad',
              ),
              GButton(
                icon: Icons.credit_card_rounded,
                iconSize: 22,
                text: 'Card',
              ),
              GButton(
                icon: FluentIcons.people_32_regular,
                iconSize: 22,
                text: 'Send',
              ),
              GButton(
                icon: Icons.receipt_long_rounded,
                iconSize: 22,
                text: 'Payments',
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.receipt_long_rounded,
                      color: _currentTab == 4
                          ? AppColors.primary
                          : AppColors.textMuted,
                      size: 22,
                    ),
                    if (unreadTransactions > 0)
                      Positioned(
                        top: -2,
                        right: -4,
                        child: ClipOval(
                          child: Container(
                              color: AppColors.danger,
                              width: 15,
                              height: 15,
                              child: Center(
                                child: Text(unreadTransactions.toString(),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                              )),
                        ),
                      )
                  ],
                ),
              ),
              GButton(
                icon: Icons.person_outline_rounded,
                iconSize: 22,
                text: 'Profile',
              ),
            ],
            selectedIndex: _currentTab,
            onTabChange: _onTabChange,
          ),
        ),
      ),
    );
  }

  void _onTabChange(index) {
    // Unfocus when leaving tabs that have a text field (International
    // Transfer's amount field, Send & Recipients' search field), so a
    // keyboard doesn't linger open on a tab that no longer needs it.
    if (_currentTab == 1 || _currentTab == 3) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    Provider.of<TabNavigationProvider>(context, listen: false)
        .updateTabs(_currentTab);
    setState(() {
      _currentTab = index;
    });
  }

  Future<bool> _onBackPress() {
    if (_currentTab == 0) {
      return Future.value(true);
    } else {
      int lastTab =
          Provider.of<TabNavigationProvider>(context, listen: false).lastTab;
      Provider.of<TabNavigationProvider>(context, listen: false)
          .removeLastTab();
      setTab(lastTab);
    }
    return Future.value(false);
  }
}



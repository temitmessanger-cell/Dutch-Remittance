import 'package:fade_shimmer/fade_shimmer.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:dutch_remit/database/currency_conversion_service.dart';
import 'package:dutch_remit/hadwin_components.dart';
import 'package:dutch_remit/screens/my_qr_code_screen.dart';
import 'package:dutch_remit/screens/enter_code_manually_screen.dart';
import 'package:dutch_remit/screens/top_up_screen.dart';
import 'package:dutch_remit/screens/withdraw_screen.dart';
import 'package:dutch_remit/screens/virtual_accounts_screen.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

import 'package:provider/provider.dart';

class HomeDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  final Function setTab;
  const HomeDashboardScreen(
      {Key? key,
      required this.user,
      required this.userAuthKey,
      required this.setTab})
      : super(key: key);

  @override
  HomeDashboardScreenState createState() => HomeDashboardScreenState();
}

class HomeDashboardScreenState extends State<HomeDashboardScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> allTransactions = [];
  bool isLoadingTransactions = true;
  late List<Map<String, dynamic>> response;
  Map<String, dynamic>? error = null;
  final CurrencyConversionService _currencyService = CurrencyConversionService();
  String _displayCurrency = 'USD';

  // Home used to stack a "Recent contacts" strip directly above a
  // 4-item transaction preview, both squeezed into whatever space was
  // left under the balance card and quick actions — which read as a
  // cramped little box rather than a real, breathing list. Switching
  // between them via tabs means whichever one is selected gets the
  // entire remaining screen height instead of splitting it.
  int _activeHomeTab = 1; // 0 = Contacts, 1 = Transactions (shown by default)

  late AnimationController _entranceController;
  late Animation<double> _balanceCardAnimation;
  late Animation<double> _quickActionsAnimation;

  @override
  void initState() {
    super.initState();
    getTransactionsFromApi();

    // Best-effort: replace the locally-tracked balance with the real
    // Eversend wallet balance as soon as the backend is reachable, so
    // "my Eversend account is loaded" is genuinely true on the Home
    // screen, not just after a deposit/withdrawal round-trip.
    WidgetsBinding.instance!.addPostFrameCallback((_) {
      Provider.of<UserLoginStateProvider>(context, listen: false)
          .syncBalanceFromEversend(widget.userAuthKey);
    });

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _balanceCardAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
    );
    _quickActionsAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.25, 1.0, curve: Curves.easeOutCubic),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String userFirstName = widget.user['first_name']?.toString() ?? '';
    final String userBalance = context.watch<UserLoginStateProvider>().bankBalance;
    final String bankName = (widget.user['bankDetails'] != null &&
            widget.user['bankDetails'].isNotEmpty)
        ? (widget.user['bankDetails'][0]['bankName']?.toString() ?? 'Account')
        : 'Account';

    Widget avatar = GestureDetector(
      onTap: goToWalletScreen,
      child: CircleAvatar(
        backgroundColor: AppColors.surfaceAlt,
        radius: 20,
        child: widget.user['avatar'] == null
            ? Text(
                userFirstName.isNotEmpty ? userFirstName[0].toUpperCase() : '?',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
              )
            : ClipOval(
                child: Image.network(
                  "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/Dutch Remit_users/${widget.user['gender']?.toString().toLowerCase() ?? ''}/${widget.user['avatar']}",
                  height: 36,
                  width: 36,
                  fit: BoxFit.cover,
                ),
              ),
      ),
    );

    // ── TOP BAR ── search field + avatar, matching the reference's
    // search-first header instead of a marketing-style hero banner.
    Widget topBar = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _goToRecipientsSearch,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: AppColors.textMuted, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "Search recipients",
                      style: TextStyle(color: AppColors.textMuted, fontSize: 14.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          avatar,
        ],
      ),
    );

    // ── BALANCE CARD ── account label, total balance, and a quick
    // glance at available funds — same data as before, reference layout.
    Widget balanceCard = Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "Hi, $userFirstName",
                style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            bankName,
            style: TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                "\$",
                style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 22,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 3),
              Flexible(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('balance-${userBalance}'),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  tween: Tween<double>(
                      begin: 0, end: double.tryParse(userBalance) ?? 0),
                  builder: (context, value, child) {
                    final bool hasDecimals = userBalance.contains('.');
                    final String displayValue = hasDecimals
                        ? value.toStringAsFixed(2)
                        : value.toStringAsFixed(0);
                    return Text(
                      displayValue,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          letterSpacing: -0.6,
                          fontWeight: FontWeight.w800,
                          height: 1.0),
                    );
                  },
                ),
              ),
              const Spacer(),
              if (context.watch<UserLoginStateProvider>().isSyncingEversendBalance)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.8, color: Colors.white.withOpacity(0.8)),
                  ),
                ),
              GestureDetector(
                onTap: _openCurrencyPicker,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "USD",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white, size: 15),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_displayCurrency != 'USD') ...[
            const SizedBox(height: 8),
            _buildConvertedAmountRow(userBalance),
          ],
        ],
      ),
    );

    // ── QUICK ACTIONS ── Send / Card / More, mirrors the reference's
    // action row directly beneath the balance card.
    Widget quickActions = Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        children: [
          _quickAction(
            icon: Icons.arrow_upward_rounded,
            label: "Send",
            isPrimary: true,
            onTap: () => _makeATransaction('debit'),
          ),
          const SizedBox(width: 8),
          _quickAction(
            icon: Icons.arrow_downward_rounded,
            label: "Request",
            isPrimary: false,
            onTap: () => _makeATransaction('credit'),
          ),
          const SizedBox(width: 8),
          _quickAction(
            icon: Icons.add_circle_outline_rounded,
            label: "Top Up",
            isPrimary: false,
            onTap: _goToTopUp,
          ),
          const SizedBox(width: 8),
          _quickAction(
            icon: Icons.account_balance_wallet_outlined,
            label: "Withdraw",
            isPrimary: false,
            onTap: _goToWithdraw,
          ),
          const SizedBox(width: 8),
          _quickActionMenu(),
        ],
      ),
    );

    return Scaffold(
        backgroundColor: AppColors.scaffold,
        body: SafeArea(
          child: Column(
            children: [
              // Header section: top bar, balance card, quick actions.
              // This scrolls along with the page on small screens, but
              // unlike before, it no longer competes with Contacts and
              // Transactions for space — those live below in their own
              // Expanded region instead of being squeezed in here too.
              SingleChildScrollView(
                child: Column(
                  children: [
                    topBar,
                    AnimatedBuilder(
                      animation: _balanceCardAnimation,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _balanceCardAnimation.value,
                          child: Transform.translate(
                            offset:
                                Offset(0, 16 * (1 - _balanceCardAnimation.value)),
                            child: child,
                          ),
                        );
                      },
                      child: balanceCard,
                    ),
                    AnimatedBuilder(
                      animation: _quickActionsAnimation,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _quickActionsAnimation.value,
                          child: Transform.translate(
                            offset:
                                Offset(0, 16 * (1 - _quickActionsAnimation.value)),
                            child: child,
                          ),
                        );
                      },
                      child: quickActions,
                    ),
                  ],
                ),
              ),

              // Tab switcher: Contacts <-> Transactions. Whichever is
              // selected gets the entire remaining screen height below,
              // instead of both being squeezed into whatever was left.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: _buildHomeTabSwitcher(),
              ),

              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: KeyedSubtree(
                    key: ValueKey(_activeHomeTab),
                    child: _activeHomeTab == 0
                        ? _buildContactsTabContent(context)
                        : _buildTransactionsTabContent(context),
                  ),
                ),
              ),
            ],
          ),
        ));
  }

  Widget _buildHomeTabSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Expanded(child: _homeTabButton(label: "Contacts", index: 0)),
          Expanded(child: _homeTabButton(label: "Transactions", index: 1)),
        ],
      ),
    );
  }

  Widget _homeTabButton({required String label, required int index}) {
    final bool isActive = _activeHomeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeHomeTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          boxShadow: isActive ? AppShadows.card : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isActive ? AppColors.primary : AppColors.textMuted),
        ),
      ),
    );
  }

  Widget _buildContactsTabContent(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: getData(
          urlPath: "/Dutch Remit/v3/all-contacts", authKey: widget.userAuthKey!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4, mainAxisSpacing: 16, crossAxisSpacing: 8),
            itemCount: 8,
            itemBuilder: (_, __) => Column(
              children: [
                FadeShimmer.round(size: 56, fadeTheme: FadeTheme.light),
                const SizedBox(height: 6),
                FadeShimmer(height: 10, width: 40, fadeTheme: FadeTheme.light),
              ],
            ),
          );
        }
        if (snapshot.data!.keys.join().toLowerCase().contains("error")) {
          return Center(
            child: Text("Couldn't load contacts",
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
          );
        }
        List<dynamic> contacts = snapshot.data!['contacts'] ?? [];
        if (contacts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline_rounded,
                      size: 36, color: AppColors.textMuted),
                  const SizedBox(height: 12),
                  Text("No contacts yet",
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                          fontSize: 15)),
                  const SizedBox(height: 4),
                  Text("Add a contact from the Recipients tab to see them here.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, mainAxisSpacing: 18, crossAxisSpacing: 8),
          itemCount: contacts.length,
          itemBuilder: (_, index) {
            final contact = contacts[index];
            final String name = contact['name']?.toString() ?? '';
            Widget avatarContent;
            if (contact['avatar'] != null && contact['avatar'].toString().isNotEmpty) {
              avatarContent = ClipOval(
                child: Image.network(
                  "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${contact['avatar']}",
                  height: 56,
                  width: 56,
                  fit: BoxFit.cover,
                ),
              );
            } else {
              avatarContent = Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary),
              );
            }
            return GestureDetector(
              onTap: () => _makeATransactionWith(contact, 'debit'),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.surfaceAlt,
                    child: avatarContent,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name.split(' ').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  Widget _buildConvertedAmountRow(String userBalance) {
    final double? amount = double.tryParse(userBalance.replaceAll(',', ''));
    if (amount == null) return const SizedBox.shrink();

    return FutureBuilder<double?>(
      key: ValueKey(_displayCurrency),
      future: _currencyService.convert(
          amount: amount, base: 'USD', target: _displayCurrency),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: Colors.white.withOpacity(0.6)),
              ),
              const SizedBox(width: 8),
              Text("Converting…",
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.6), fontSize: 12.5)),
            ],
          );
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return Text("Conversion unavailable right now",
              style: TextStyle(
                  color: Colors.white.withOpacity(0.55), fontSize: 12.5));
        }
        final converted = snapshot.data!;
        return AnimatedOpacity(
          opacity: 1,
          duration: const Duration(milliseconds: 250),
          child: Text(
            "≈ ${converted.toStringAsFixed(2)} $_displayCurrency",
            style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }

  void _openCurrencyPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text("Display currency",
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 4),
                Text("Live rates from the European Central Bank",
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                const SizedBox(height: 12),
                ...CurrencyConversionService.supportedCurrencies.map((code) {
                  final bool isSelected = code == _displayCurrency;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(code,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                            fontSize: 15)),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded,
                            color: AppColors.primary, size: 20)
                        : null,
                    onTap: () {
                      setState(() => _displayCurrency = code);
                      Navigator.of(context).pop();
                    },
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isPrimary ? AppColors.primary : AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isPrimary ? Colors.white : AppColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActionMenu() {
    return Expanded(
      child: PopupMenuButton<_ScanOptions>(
        offset: const Offset(0, 56),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md)),
        onSelected: (value) {
          if (value == _ScanOptions.ScanQRCode) {
            Navigator.push(
                    context, SlideRightRoute(page: EnterCodeManuallyScreen()))
                .whenComplete(() => setState(() {}));
          } else if (value == _ScanOptions.MyQRCode) {
            Navigator.push(context,
                    SlideRightRoute(page: MyQrCodeScreen(user: widget.user)))
                .whenComplete(() => setState(() {}));
          } else {
            Navigator.push(
                    context,
                    SlideRightRoute(
                        page: VirtualAccountsScreen(
                            user: widget.user, userAuthKey: widget.userAuthKey)))
                .whenComplete(() => setState(() {}));
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _ScanOptions.ScanQRCode,
            child: Row(children: [
              Icon(FluentIcons.qr_code_28_regular, size: 18, color: AppColors.ink),
              const SizedBox(width: 10),
              Text("Scan QR Code"),
            ]),
          ),
          PopupMenuItem(
            value: _ScanOptions.MyQRCode,
            child: Row(children: [
              Icon(FluentIcons.qr_code_28_regular, size: 18, color: AppColors.ink),
              const SizedBox(width: 10),
              Text("My QR Code"),
            ]),
          ),
          PopupMenuItem(
            value: _ScanOptions.VirtualAccounts,
            child: Row(children: [
              Icon(Icons.account_balance_rounded, size: 18, color: AppColors.ink),
              const SizedBox(width: 10),
              Text("Virtual Accounts"),
            ]),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  FluentIcons.more_vertical_28_regular,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "More",
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }


  void _makeATransaction(String transactionType) {
    Navigator.push(
            context,
            SlideRightRoute(
                page: AvailableBusinessesAndContactsScreen(
                    transactionType: transactionType, user: widget.user)))
        .then((value) => getTransactionsFromApi());
  }

  void _makeATransactionWith(
      Map<String, dynamic> otherParty, String transactionType) {
    Navigator.push(
            context,
            SlideRightRoute(
                page: FundTransferScreen(
                    otherParty: otherParty, transactionType: transactionType)))
        .then((value) => getTransactionsFromApi());
  }

  Widget _buildTransactionsTabContent(BuildContext context) {
    if (error != null) {
      WidgetsBinding.instance!
          .addPostFrameCallback((_) => showErrorAlert(context, error!));

      return activitiesLoadingList(6);
    } else if (isLoadingTransactions) {
      return activitiesLoadingList(6);
    } else if (allTransactions.isEmpty) {
      // Genuinely empty (fetch succeeded, there's just nothing yet) —
      // distinct from "still loading", which used to shimmer forever
      // and never resolve to this message.
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.receipt_24_regular,
                  size: 36, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(
                "No transactions yet",
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                "Your activity will show up here once you send or receive money.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    } else {
      List<dynamic> currentTransactions = allTransactions;

      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        itemCount: currentTransactions.length,
        itemBuilder: (BuildContext context, int index) {
          Widget transactionMemberImage = FutureBuilder<int>(
            future: checkUrlValidity(
                "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${currentTransactions[index]['transactionMemberAvatar']}"),
            builder: (context, snapshot) {
              if (currentTransactions[index]
                      .containsKey('transactionMemberBusinessWebsite') &&
                  currentTransactions[index]
                        .containsKey('transactionMemberAvatar') &&
                      currentTransactions[index]['transactionMemberAvatar'] != null) {
                return ClipOval(
                  child: AspectRatio(
                    aspectRatio: 1.0 / 1.0,
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        AppColors.primary,
                        BlendMode.color,
                      ),
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          Colors.grey,
                          BlendMode.saturation,
                        ),
                        child: Image.network(
                          "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${currentTransactions[index]['transactionMemberAvatar']}",
                          height: 64,
                          width: 64,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                );
              } else if (currentTransactions[index]
                      .containsKey('transactionMemberEmail') &&
                  currentTransactions[index]
                        .containsKey('transactionMemberAvatar') &&
                      currentTransactions[index]['transactionMemberAvatar'] != null &&
                  snapshot.hasData) {
                if (snapshot.data == 404) {
                  return ClipOval(
                    child: AspectRatio(
                      aspectRatio: 1.0 / 1.0,
                      child: Image.network(
                        "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/Dutch Remit_users/${currentTransactions[index]['transactionMemberGender']?.toString().toLowerCase() ?? ''}/${currentTransactions[index]['transactionMemberAvatar']}",
                        height: 64,
                        width: 64,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                } else {
                  return ClipOval(
                    child: AspectRatio(
                      aspectRatio: 1.0 / 1.0,
                      child: Image.network(
                        "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${currentTransactions[index]['transactionMemberAvatar']}",
                        height: 64,
                        width: 64,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                }
              } else {
                return Text(
                  currentTransactions[index]['transactionMemberName'][0]
                      .toUpperCase(),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary),
                );
              }
            },
          );

          return TweenAnimationBuilder<double>(
            key: ValueKey('txn-anim-$index'),
            duration: Duration(milliseconds: 250 + (index * 40).clamp(0, 400)),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(begin: 0, end: 1),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 12 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  onTap: _viewAllActivities,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.all(Radius.circular(AppRadii.lg)),
                      boxShadow: AppShadows.card,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      leading: CircleAvatar(
                          radius: 26,
                          backgroundColor: AppColors.surfaceAlt,
                          child: transactionMemberImage),
                      title: Text(
                        currentTransactions[index]['transactionMemberName'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          dateFormatter(
                              currentTransactions[index]['dateGroup'],
                              DateTime.parse(currentTransactions[index]
                                  ['transactionDate'])),
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted),
                        ),
                      ),
                      trailing: Text(
                        currentTransactions[index]['transactionType'] ==
                                "credit"
                            ? "+\$${currentTransactions[index]['transactionAmount'].toString()}"
                            : "-\$${currentTransactions[index]['transactionAmount'].toString()}",
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: currentTransactions[index]
                                        ['transactionType'] ==
                                    "credit"
                                ? AppColors.success
                                : AppColors.danger),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
  }

  void goToWalletScreen() {
    widget.setTab(2);
    Provider.of<TabNavigationProvider>(context, listen: false).updateTabs(0);
  }

  void _goToTopUp() {
    Navigator.push(context, SlideRightRoute(page: TopUpScreen(user: widget.user, userAuthKey: widget.userAuthKey)))
        .then((_) => getTransactionsFromApi());
  }

  void _goToWithdraw() {
    Navigator.push(context, SlideRightRoute(page: WithdrawScreen(user: widget.user, userAuthKey: widget.userAuthKey)))
        .then((_) => getTransactionsFromApi());
  }

  void _goToRecipientsSearch() {
    Provider.of<TabNavigationProvider>(context, listen: false).updateTabs(0);
    widget.setTab(3);
  }

  void _viewAllActivities() {
    Provider.of<TabNavigationProvider>(context, listen: false).updateTabs(0);
    widget.setTab(4);
  }

  void _updateTransactions() {
    setState(() {
      allTransactions
          .sort((a, b) => b['transactionDate'].compareTo(a['transactionDate']));
      for (var transaction in allTransactions) {
        String dateResponse =
            customGroup(DateTime.parse(transaction['transactionDate']));
        transaction['dateGroup'] = dateResponse;
      }
    });
  }

  void getTransactionsFromApi() async {
    response = await Future.wait([
      getData(
          urlPath: "/Dutch Remit/v1/all-transactions", authKey: widget.userAuthKey!),
      SuccessfulTransactionsStorage().getSuccessfulTransactions()
    ]);

    if (response[0].keys.join().toLowerCase().contains("error") ||
        response[1].keys.join().toLowerCase().contains("error")) {
      if (mounted) {
        setState(() {
          error = response[0].keys.join().toLowerCase().contains("error")
              ? response[0]
              : response[1];
          isLoadingTransactions = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          allTransactions = [
            ...response[0]['transactions'],
            ...response[1]['transactions']
          ];
          isLoadingTransactions = false;
        });
        _updateTransactions();
      }
    }
  }
}

enum _ScanOptions { ScanQRCode, MyQRCode, VirtualAccounts }



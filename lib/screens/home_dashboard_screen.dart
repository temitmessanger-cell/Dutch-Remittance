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
import 'package:dutch_remit/screens/crypto_screen.dart';
import 'package:dutch_remit/screens/currency_swap_screen.dart';
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

  // History tab (Contacts <-> History): merges real transactions with
  // real notifications (GET /api/v1/notifications, same endpoint the
  // Payments tab's Notifications upper nav already uses) into one
  // horizontal, 2-row feed — see _buildHistoryTabContent below.
  List<Map<String, dynamic>> _historyNotifications = [];
  bool _isLoadingHistoryNotifications = true;

  // The only currencies the home balance card can display, per
  // product decision — NGN and GHS require a bank account (see
  // VirtualAccountsScreen / klasha.js) to actually be usable, so they
  // show as unavailable until one exists rather than being hidden
  // entirely, so the user knows the path to unlock them.
  static const List<Map<String, String>> _homeCurrencies = [
    {'code': 'XAF', 'name': 'CFA Franc (Central Africa)', 'flag': '🇨🇲'},
    {'code': 'USD', 'name': 'US Dollar', 'flag': '🇺🇸'},
    {'code': 'USDT', 'name': 'Tether (USDT)', 'flag': '₮'},
    {'code': 'NGN', 'name': 'Nigerian Naira', 'flag': '🇳🇬'},
    {'code': 'GHS', 'name': 'Ghanaian Cedi', 'flag': '🇬🇭'},
  ];

  // Which of NGN/GHS the user actually has a bank account for —
  // loaded once on init from the same endpoint VirtualAccountsScreen
  // uses, so the two screens never disagree about what's unlocked.
  Set<String> _bankAccountCurrencies = {};
  bool _loadedBankAccounts = false;

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
    _loadBankAccounts();
    _loadHistoryNotifications();

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
                        _displayCurrency,
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

              // ── SWAP CARD ── A visible, dedicated home-screen
              // entry point for converting between the wallet's
              // supported currencies — not buried in the overflow
              // menu, matching how prominent this feature should be
              // per product requirement. Real quote + real execute
              // (CurrencySwapScreen -> POST /api/v1/rates/exchange-quotation,
              // POST /api/v1/rates/exchange).
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: InkWell(
                  onTap: () => Navigator.push(
                          context,
                          SlideRightRoute(
                              page: CurrencySwapScreen(
                                  user: widget.user, userAuthKey: widget.userAuthKey)))
                      .whenComplete(() => setState(() {})),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      boxShadow: AppShadows.card,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.swap_horiz_rounded, color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Swap currencies",
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
                              const SizedBox(height: 2),
                              Text("Convert between USD, XAF, NGN and GHS in your wallet",
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                      ],
                    ),
                  ),
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
                        : _buildHistoryTabContent(context),
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
          Expanded(child: _homeTabButton(label: "History", index: 1)),
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
        // Real fix: this used to be a vertically-scrolling
        // GridView(crossAxisCount: 4) — a wrapping grid, not the
        // horizontal "recent/most-contacted" strip the home screen
        // is supposed to show. Now a horizontally-scrolling grid with
        // a fixed 2-row height, matching "2 horizontal columns" —
        // shows only the most recent/most-contacted people at a
        // glance without pushing the rest of the home screen down.
        if (!snapshot.hasData) {
          return SizedBox(
            height: 172,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 14),
              itemCount: 6,
              itemBuilder: (_, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeShimmer.round(size: 56, fadeTheme: FadeTheme.light),
                  const SizedBox(height: 6),
                  FadeShimmer(height: 10, width: 40, fadeTheme: FadeTheme.light),
                ],
              ),
            ),
          );
        }
        if (snapshot.data!.keys.join().toLowerCase().contains("error")) {
          return SizedBox(
            height: 172,
            child: Center(
              child: Text("Couldn't load contacts",
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
            ),
          );
        }
        List<dynamic> contacts = snapshot.data!['contacts'] ?? [];
        if (contacts.isEmpty) {
          return SizedBox(
            height: 172,
            child: Center(
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
            ),
          );
        }
        // Recent/most-contacted only — capped so the horizontal strip
        // stays a quick-glance shortcut, not a full contact list (the
        // full list already lives on the Recipients tab).
        final recentContacts = contacts.take(12).toList();
        return SizedBox(
          height: 172,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 18, crossAxisSpacing: 14),
            itemCount: recentContacts.length,
            itemBuilder: (_, index) {
              final contact = recentContacts[index];
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
                child: SizedBox(
                  width: 68,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                ),
              );
            },
          ),
        );
      },
    );
  }


  /// Formats a transaction's signed amount with its real currency —
  /// e.g. "+62,650 XAF" or "-100.00 USD" — instead of the previous
  /// hardcoded "$" prefix regardless of what currency the transaction
  /// actually was in. Falls back to "$" only for older locally-stored
  /// transactions saved before the 'currency' field existed on the
  /// receipt object, so historical entries don't break.
  String _formatTransactionAmount(Map<String, dynamic> transaction) {
    final isCredit = transaction['transactionType'] == 'credit';
    final sign = isCredit ? '+' : '-';
    final amount = transaction['transactionAmount']?.toString() ?? '0';
    final currency = transaction['currency']?.toString();
    if (currency == null) return '$sign\$$amount';
    return '$sign$amount $currency';
  }

  Future<void> _loadHistoryNotifications() async {
    if (widget.userAuthKey == null || widget.userAuthKey!.trim().isEmpty) {
      setState(() => _isLoadingHistoryNotifications = false);
      return;
    }
    final result =
        await getData(urlPath: "/api/v1/notifications", authKey: widget.userAuthKey);
    if (!mounted) return;
    final list = result['notifications'] is List
        ? List<Map<String, dynamic>>.from(
            (result['notifications'] as List).map((n) => Map<String, dynamic>.from(n)))
        : <Map<String, dynamic>>[];
    setState(() {
      _historyNotifications = list;
      _isLoadingHistoryNotifications = false;
    });
  }

  Future<void> _loadBankAccounts() async {
    if (widget.userAuthKey == null || widget.userAuthKey!.trim().isEmpty) {
      setState(() => _loadedBankAccounts = true);
      return;
    }
    final result = await getData(
        urlPath: "/api/v1/klasha/virtual-accounts/mine", authKey: widget.userAuthKey);
    if (!mounted) return;
    final accounts = result['virtualAccounts'] is List
        ? List<Map<String, dynamic>>.from(
            (result['virtualAccounts'] as List).map((a) => Map<String, dynamic>.from(a)))
        : <Map<String, dynamic>>[];
    setState(() {
      _bankAccountCurrencies =
          accounts.map((a) => a['currency']?.toString().toUpperCase() ?? '').toSet();
      _loadedBankAccounts = true;
    });
  }

  /// Whether [code] can be selected as a display currency right now.
  /// XAF, USD and USDT are always available; NGN and GHS require a
  /// bank account in that currency first (see VirtualAccountsScreen).
  bool _isCurrencyUnlocked(String code) {
    if (code == 'NGN' || code == 'GHS') {
      return _bankAccountCurrencies.contains(code);
    }
    return true;
  }

  Widget _buildConvertedAmountRow(String userBalance) {
    final double? amount = double.tryParse(userBalance.replaceAll(',', ''));
    if (amount == null) return const SizedBox.shrink();

    // USDT tracks USD 1:1 — no conversion call needed or meaningful.
    if (_displayCurrency == 'USDT') {
      return Text(
        "≈ ${amount.toStringAsFixed(2)} USDT",
        style: TextStyle(
            color: Colors.white.withOpacity(0.7), fontSize: 13, fontWeight: FontWeight.w600),
      );
    }

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
                Text("Your wallet's real balance stays in USD — this only changes how it's shown.",
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                const SizedBox(height: 12),
                ..._homeCurrencies.map((c) {
                  final code = c['code']!;
                  final bool isSelected = code == _displayCurrency;
                  final bool isUnlocked = _isCurrencyUnlocked(code);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    enabled: isUnlocked,
                    leading: Text(c['flag']!, style: const TextStyle(fontSize: 20)),
                    title: Text(code,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isUnlocked ? AppColors.ink : AppColors.textMuted,
                            fontSize: 15)),
                    subtitle: !isUnlocked
                        ? Text("Unavailable — create a $code bank account",
                            style: TextStyle(fontSize: 11.5, color: AppColors.warning))
                        : Text(c['name']!,
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded,
                            color: AppColors.primary, size: 20)
                        : (!isUnlocked
                            ? TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => VirtualAccountsScreen(
                                          user: widget.user, userAuthKey: widget.userAuthKey),
                                    ),
                                  );
                                },
                                child: Text("Create",
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                              )
                            : null),
                    onTap: isUnlocked
                        ? () {
                            setState(() => _displayCurrency = code);
                            Navigator.of(context).pop();
                          }
                        : null,
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
          } else if (value == _ScanOptions.Crypto) {
            Navigator.push(
                    context,
                    SlideRightRoute(
                        page: CryptoScreen(
                            user: widget.user, userAuthKey: widget.userAuthKey)))
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
              Text("Bank Accounts"),
            ]),
          ),
          PopupMenuItem(
            value: _ScanOptions.Crypto,
            child: Row(children: [
              Icon(Icons.currency_bitcoin_rounded, size: 18, color: AppColors.ink),
              const SizedBox(width: 10),
              Text("View USDT Address"),
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

  /// The "History" tab: merges real transactions with real
  /// notifications into one horizontal, 2-row card feed — matching
  /// the Contacts strip's layout above (scrollDirection: horizontal,
  /// SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2)).
  /// A deliberately simpler card than the old vertical transaction
  /// list (_buildTransactionsTabContent below, kept but no longer
  /// called): no per-item avatar-image network resolution, since a
  /// small horizontal card doesn't have room for that detail the way
  /// a full-width list row did — name/amount/date/type icon only.
  /// Tapping a transaction card still opens the same real receipt
  /// dialog as before; tapping a notification card marks it read via
  /// the same PATCH /api/v1/notifications/:id the Payments tab uses.
  Widget _buildHistoryTabContent(BuildContext context) {
    if (error != null) {
      WidgetsBinding.instance!
          .addPostFrameCallback((_) => showErrorAlert(context, error!));
      return _historyShimmerGrid();
    }
    if (isLoadingTransactions || _isLoadingHistoryNotifications) {
      return _historyShimmerGrid();
    }

    // Merge: every transaction becomes a card, every notification
    // becomes a card, sorted together by recency so the strip reads
    // as one real activity feed rather than two separate lists stuck
    // together.
    final List<_HistoryItem> items = [
      ...allTransactions.map((t) => _HistoryItem.fromTransaction(Map<String, dynamic>.from(t))),
      ..._historyNotifications.map((n) => _HistoryItem.fromNotification(n)),
    ]..sort((a, b) => b.sortDate.compareTo(a.sortDate));

    if (items.isEmpty) {
      return SizedBox(
        height: 172,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.receipt_24_regular, size: 36, color: AppColors.textMuted),
                const SizedBox(height: 12),
                Text("Nothing yet",
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink, fontSize: 15)),
                const SizedBox(height: 4),
                Text("Transfers and updates will show up here.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    final capped = items.take(20).toList();
    return SizedBox(
      height: 172,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.6),
        itemCount: capped.length,
        itemBuilder: (context, index) => _historyCard(capped[index]),
      ),
    );
  }

  Widget _historyShimmerGrid() {
    return SizedBox(
      height: 172,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.6),
        itemCount: 6,
        itemBuilder: (_, __) => ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: FadeShimmer(height: 74, width: 160, fadeTheme: FadeTheme.light, radius: 12),
        ),
      ),
    );
  }

  Widget _historyCard(_HistoryItem item) {
    return InkWell(
      onTap: () {
        if (item.isNotification && item.raw['id'] != null) {
          patchData(
            urlPath: "/api/v1/notifications/${item.raw['id']}",
            data: {"isRead": true},
            authKey: widget.userAuthKey,
          );
        }
      },
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: item.iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(item.icon, size: 16, color: item.iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
                              // .toLocal() — real fix. DateTime.parse()
                              // on a backend timestamp (Postgres
                              // timestamptz, which serializes with a
                              // UTC/offset marker) correctly produces
                              // a UTC-flagged DateTime; reading
                              // .hour/.minute off it directly without
                              // converting to local time shows the
                              // UTC hour, not the Cameroon-local one —
                              // exactly the confirmed "an hour ago
                              // instead of the current time" bug
                              // (Cameroon is UTC+1).
                              DateTime.parse(currentTransactions[index]
                                      ['transactionDate'])
                                  .toLocal()),
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted),
                        ),
                      ),
                      trailing: Text(
                        _formatTransactionAmount(currentTransactions[index]),
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
            customGroup(DateTime.parse(transaction['transactionDate']).toLocal());
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

enum _ScanOptions { ScanQRCode, MyQRCode, VirtualAccounts, Crypto }

/// A single card in the History strip — either a real transaction or
/// a real notification, normalized to one shape so both can be
/// sorted and rendered together.
class _HistoryItem {
  final bool isNotification;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final DateTime sortDate;
  final Map<String, dynamic> raw;

  _HistoryItem({
    required this.isNotification,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.sortDate,
    required this.raw,
  });

  factory _HistoryItem.fromTransaction(Map<String, dynamic> txn) {
    final type = txn['transactionType']?.toString() ?? '';
    final isCredit = type == 'credit';
    final name = txn['transactionMemberName']?.toString() ?? 'Transaction';
    final amount = txn['transactionAmount']?.toString() ?? '';
    final dateStr = txn['transactionDate']?.toString();
    final date = dateStr != null ? DateTime.tryParse(dateStr) ?? DateTime.now() : DateTime.now();
    return _HistoryItem(
      isNotification: false,
      title: name,
      subtitle: isCredit ? "+$amount" : "-$amount",
      icon: isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
      iconColor: isCredit ? AppColors.success : AppColors.primary,
      sortDate: date,
      raw: txn,
    );
  }

  factory _HistoryItem.fromNotification(Map<String, dynamic> n) {
    final dateStr = n['created_at']?.toString();
    final date = dateStr != null ? DateTime.tryParse(dateStr) ?? DateTime.now() : DateTime.now();
    return _HistoryItem(
      isNotification: true,
      title: n['title']?.toString() ?? 'Notification',
      subtitle: n['body']?.toString() ?? '',
      icon: Icons.notifications_rounded,
      iconColor: n['is_read'] == true ? AppColors.textMuted : AppColors.warning,
      sortDate: date,
      raw: n,
    );
  }
}



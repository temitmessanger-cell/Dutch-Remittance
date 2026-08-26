import 'package:flutter/material.dart';
import 'package:dutch_remit/hadwin_components.dart';
import 'package:dutch_remit/screens/card_to_card_transfer_screen.dart';
import 'package:dutch_remit/screens/create_virtual_card_screen.dart';
import 'package:dutch_remit/screens/card_link_verification_screen.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

class WalletScreen extends StatefulWidget {
  final Function setTab;
  final Map<String, dynamic> user;
  final String? userAuthKey;
  const WalletScreen({Key? key, required this.user, required this.setTab, this.userAuthKey})
      : super(key: key);

  @override
  _WalletScreenState createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  CardsStorage availableCards = CardsStorage();
  Map<String, dynamic>? _primaryCard;
  late Future<Map<String, dynamic>> _cardsFuture;

  @override
  void initState() {
    super.initState();
    // CardsStorage is backend-driven now (no local Hive cache). Seed it
    // with the auth key so it can fetch this user's cards, then reuse a
    // single cached future rather than refetching on every rebuild.
    _cardsFuture = _initAndLoadCards();
    _loadPrimaryCard();
  }

  Future<Map<String, dynamic>> _initAndLoadCards() async {
    final key = widget.userAuthKey;
    if (key != null && key.trim().isNotEmpty) {
      await availableCards.initializeAvailableCards(key);
    }
    return availableCards.readAvailableCards();
  }

  Future<void> _loadPrimaryCard() async {
    final data = await _cardsFuture;
    final cards = data['availableCards'] as List<dynamic>? ?? [];
    if (mounted && cards.isNotEmpty) {
      setState(() => _primaryCard = Map<String, dynamic>.from(cards.first));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.scaffold,
        appBar: AppBar(
          title: Text("Cards",
              style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w700)),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _cardsFuture,
                  builder: _buildFeaturedCardSection,
                ),
              ),
              SliverToBoxAdapter(child: _buildBankLinkingSection()),
              SliverToBoxAdapter(child: _buildAccountInfoSection()),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ));
  }

  Widget _buildFeaturedCardSection(
      BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
    List<dynamic> cardData = [];
    if (snapshot.hasData && snapshot.data!.containsKey('availableCards')) {
      cardData = snapshot.data!['availableCards'];
    }

    if (!snapshot.hasData) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(height: 180, child: availableCardsLoadingList(1)),
      );
    }

    if (cardData.isEmpty) {
      return _buildEmptyCardState();
    }

    final featured = cardData.first;
    if (_primaryCard == null || _primaryCard!['cardNumber'] != featured['cardNumber']) {
      WidgetsBinding.instance!.addPostFrameCallback((_) {
        if (mounted) setState(() => _primaryCard = Map<String, dynamic>.from(featured));
      });
    }
    final List<dynamic> remaining = cardData.skip(1).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: _buildCardVisual(featured),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            children: [
              _circleAction(
                icon: Icons.add_rounded,
                label: "Add card",
                onTap: goToAddCardScreen,
              ),
              const SizedBox(width: 16),
              _circleAction(
                icon: Icons.info_outline_rounded,
                label: "Card details",
                onTap: () => _showCardDetails(featured),
              ),
              const SizedBox(width: 16),
              _circleAction(
                icon: Icons.delete_outline_rounded,
                label: "Remove card",
                onTap: () => _deleteCardDialogBox(featured['cardNumber']),
              ),
            ],
          ),
        ),
        if (remaining.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
            child: Text(
              "OTHER CARDS",
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: remaining
                  .map((card) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildCardListTile(card),
                      ))
                  .toList(),
            ),
          ),
        ],
        Padding(
          padding: EdgeInsets.fromLTRB(20, remaining.isEmpty ? 16 : 4, 20, 0),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.md),
            onTap: goToAddCardScreen,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text("Add a card",
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCardState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
      child: Column(
        children: [
          Icon(Icons.credit_card_off_outlined, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text("No cards added yet",
              style: TextStyle(
                  color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 6),
          Text("Add a card to start managing your payments",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: goToAddCardScreen,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: Text("Add a card",
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildCardVisual(Map<String, dynamic> card) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "DR",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/Dutch Remit_payment_system/square_card_brands/${card['cardBrand']?.toString().replaceAll(' ', '-').toLowerCase() ?? 'unknown'}.png",
                  width: 36,
                  height: 36,
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
          Text(
            _formatCardNumber(card['cardNumber']),
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4),
          ),
          const SizedBox(height: 16),
          Text(
            card['cardBrand'] ?? '',
            style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _circleAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardListTile(Map<String, dynamic> card) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: () => _deleteCardDialogBox(card['cardNumber']),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: AppShadows.card,
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6.18),
              child: Container(
                  color: Colors.white,
                  child: Image.network(
                    "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/Dutch Remit_payment_system/square_card_brands/${card['cardBrand']?.toString().replaceAll(' ', '-').toLowerCase() ?? 'unknown'}.png",
                    width: 40,
                    height: 40,
                  )),
            ),
            title: Text(
              card['cardBrand'] ?? '',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.ink, fontSize: 15),
            ),
            subtitle: Text(_formatCardNumber(card['cardNumber']),
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            trailing:
                Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildBankLinkingSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "VIRTUAL CARD & TRANSFERS",
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6),
          ),
          const SizedBox(height: 10),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                children: [
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: Icon(Icons.add_card_rounded,
                          color: AppColors.primary, size: 18),
                    ),
                    title: Text("Add a Card",
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                            fontSize: 15)),
                    subtitle: Text("Link a Mastercard debit or credit card",
                        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 20),
                    onTap: () => goToAddCardScreen(),
                  ),
                  Divider(height: 1, color: AppColors.divider, indent: 16, endIndent: 16),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: Icon(Icons.credit_score_rounded,
                          color: AppColors.primary, size: 18),
                    ),
                    title: Text("Create a Virtual Card",
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                            fontSize: 15)),
                    subtitle: Text("Issued in 3 steps",
                        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 20),
                    onTap: () => Navigator.push(
                        context,
                        SlideRightRoute(
                            page: CreateVirtualCardScreen(
                                user: widget.user, userAuthKey: widget.userAuthKey)))
                        .then((_) {
                      _loadPrimaryCard();
                      setState(() {});
                    }),
                  ),
                  Divider(height: 1, color: AppColors.divider, indent: 16, endIndent: 16),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: Icon(Icons.swap_horiz_rounded,
                          color: AppColors.primary, size: 18),
                    ),
                    title: Text("Card to Card transfer",
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                            fontSize: 15)),
                    subtitle: Text("Send from one of your cards to another",
                        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 20),
                    onTap: () => Navigator.push(context,
                        SlideRightRoute(
                            page: CardToCardTransferScreen(
                                user: widget.user, userAuthKey: widget.userAuthKey))),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountInfoSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "ACCOUNT",
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6),
          ),
          const SizedBox(height: 10),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                children: [
                  _accountInfoRow("Card holder name", _cardHolderName()),
                  Divider(height: 1, color: AppColors.divider, indent: 16, endIndent: 16),
                  _accountInfoRow("Card type", _cardType()),
                  Divider(height: 1, color: AppColors.divider, indent: 16, endIndent: 16),
                  _accountInfoRow("Card status", _cardStatus()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _cardHolderName() {
    final holder = _primaryCard?['cardHolder']?.toString().trim();
    if (holder != null && holder.isNotEmpty) return holder;
    return _displayName(widget.user);
  }

  String _cardType() {
    final brand = _primaryCard?['cardBrand']?.toString().trim();
    if (brand == null || brand.isEmpty || brand == 'default') return 'No card added';
    return brand[0].toUpperCase() + brand.substring(1);
  }

  String _cardStatus() {
    if (_primaryCard == null) return 'No card added';
    return 'Active';
  }

  String _displayName(Map<String, dynamic> user) {
    final first = user['first_name']?.toString().trim() ?? '';
    final last = user['last_name']?.toString().trim() ?? '';
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    if (user.isEmpty) return 'Guest';
    return user['username']?.toString() ?? 'Guest';
  }

  Widget _accountInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 14.5)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 14.5),
            ),
          ),
        ],
      ),
    );
  }

  void _showCardDetails(Map<String, dynamic> card) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg)),
              title: Text(card['cardBrand'] ?? 'Card',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Card number",
                      style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  Text(_formatCardNumber(card['cardNumber'], encrypt: false),
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text("Close", style: TextStyle(color: AppColors.primary)),
                ),
              ],
            ));
  }

  void goToAddCardScreen() => Navigator.push(
      context,
      SlideRightRoute(
          page: CardLinkVerificationScreen(user: widget.user, userAuthKey: widget.userAuthKey)))
          .then((value) {
        setState(() {});
     
      });


  //? FUNCTION FOR FORMATTING CARD NUMBER
  String _formatCardNumber(String currentCardNumber, {bool encrypt = true}) {
    String formattedCardNumber = "";
    String cardCopy = currentCardNumber;
    cardCopy = cardCopy.replaceAll(' ', '');
    if (encrypt) {
      cardCopy = cardCopy[0] +
          '*' * (cardCopy.length - 6) +
          cardCopy.substring(cardCopy.length - 5);
    }
    if (RegExp(r'^3[47]').hasMatch(currentCardNumber)) {
      for (var i = 0; i < cardCopy.length; i++) {
        formattedCardNumber += cardCopy[i];
        if (i == 3 || i == 9) {
          formattedCardNumber += ' ';
        }
      }
    } else {
      for (var i = 0; i < cardCopy.length; i++) {
        formattedCardNumber += cardCopy[i];
        if ((i + 1) % 4 == 0) {
          formattedCardNumber += ' ';
        }
      }
    }
    return formattedCardNumber.trim();
  }

  void _deleteCardDialogBox(String cardNumber) {
    ButtonStyle deleteButtonStyle = ElevatedButton.styleFrom(
      backgroundColor: AppColors.danger,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
    );
    ButtonStyle cancelButtonStyle = ElevatedButton.styleFrom(
      backgroundColor: AppColors.surfaceAlt,
      foregroundColor: AppColors.ink,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
    );
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg)),
              title: Text(
                "Delete Card?",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              content: Text(
                "Are you sure, you want to delete Card with number\n${_formatCardNumber(cardNumber, encrypt: false)}?",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkMuted),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 48,
                          width: 100,
                          child: ElevatedButton(
                              onPressed: () => _deleteSelectedCard(cardNumber),
                              child: Text('Delete'),
                              style: deleteButtonStyle
                              ),
                        ),
                        SizedBox(
                          width: 16,
                        ),
                        SizedBox(
                          height: 48,
                          width: 100,
                          child: ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: Text('Cancel'),
                              style: cancelButtonStyle),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 20,
                    ),
                  ],
                )
              ],
            ));
  }

  Future<void> _deleteSelectedCard(String cardNumber) async {
    bool cardDeletionStatus = await availableCards.deleteCard(cardNumber);
    if (cardDeletionStatus) {
      setState(() {});
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pop();
    }
  }
}



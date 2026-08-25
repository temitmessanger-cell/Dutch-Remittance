import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/screens/international_transfer_screen.dart' show GlobalTransferTabContent;
import 'package:dutch_remit/screens/africa_corridor_screen.dart';
import 'package:dutch_remit/screens/gifts_screen.dart';
import 'package:dutch_remit/screens/quick_transfer_screen.dart';
import 'package:dutch_remit/screens/explore_product_screen.dart';

/// The "Send Abroad" bottom-nav tab's home: a horizontal sub-navigation
/// bar switching between four real, distinct sending experiences —
/// Global Transfer (any of the 31 currencies this app can really
/// price), Diaspora to Africa, Africa to Africa, and Gifts — rather
/// than cramming all of that into one screen.
class SendAbroadHubScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String userAuthKey;
  const SendAbroadHubScreen(
      {Key? key, required this.user, required this.userAuthKey})
      : super(key: key);

  @override
  State<SendAbroadHubScreen> createState() => _SendAbroadHubScreenState();
}

class _SendAbroadHubScreenState extends State<SendAbroadHubScreen> {
  int _activeSubTab = 0;

  static const List<String> _subTabLabels = [
    "Global Transfer",
    "Diaspora to Africa",
    "Africa to Africa",
    "Quick Transfer",
    "Explore Product",
    "Gifts",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Send Abroad",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 19)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _subTabLabels.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final bool isActive = _activeSubTab == index;
                  return GestureDetector(
                    onTap: () => setState(() => _activeSubTab = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.primary : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        _subTabLabels[index],
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isActive ? Colors.white : AppColors.inkMuted),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(_activeSubTab),
                  child: _buildActiveSubTab(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSubTab() {
    switch (_activeSubTab) {
      case 0:
        return GlobalTransferTabContent(user: widget.user);
      case 1:
        return AfricaCorridorScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          title: "Diaspora to Africa",
          subtitle:
              "Send money from anywhere in the world straight to family and friends across Africa.",
          variant: AfricaCorridorVariant.diaspora,
        );
      case 2:
        return AfricaCorridorScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          title: "Africa to Africa",
          subtitle: "Send money between African countries, fast and transparently.",
          variant: AfricaCorridorVariant.africaToAfrica,
        );
      case 3:
        return QuickTransferScreen(user: widget.user, userAuthKey: widget.userAuthKey);
      case 4:
        return ExploreProductScreen(user: widget.user, userAuthKey: widget.userAuthKey);
      case 5:
        return GiftsScreen(user: widget.user, userAuthKey: widget.userAuthKey);
      default:
        return GlobalTransferTabContent(user: widget.user);
    }
  }
}

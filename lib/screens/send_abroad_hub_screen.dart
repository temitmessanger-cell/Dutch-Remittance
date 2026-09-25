import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/screens/global_bank_transfer_screen.dart';
import 'package:dutch_remit/screens/africa_corridor_screen.dart';
import 'package:dutch_remit/screens/gifts_screen.dart';
import 'package:dutch_remit/screens/quick_transfer_screen.dart';
import 'package:dutch_remit/screens/explore_product_screen.dart';
import 'package:dutch_remit/utilities/african_country_data.dart';
import 'package:dutch_remit/utilities/payout_country_data.dart';

/// The "Send Abroad" bottom-nav tab's home: a horizontal sub-navigation
/// bar switching between the platform's seven explicit geographic
/// corridors while reusing the existing transfer screen designs.
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
    "Africa → Africa",
    "Quick Transfer",
    "Explore Product",
    "Gifts",
    "United States → Africa",
    "Europe → Africa",
    "Africa → United States",
    "Africa → Europe",
    "United States → Europe",
    "Europe → United States",
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
        return GlobalBankTransferScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
        );
      case 1:
        return AfricaCorridorScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          title: "Diaspora to Africa",
          subtitle: "Send money from anywhere in the world straight to family and friends across Africa.",
          variant: AfricaCorridorVariant.diaspora,
        );
      case 2:
        return AfricaCorridorScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          title: "Africa → Africa",
          subtitle: "Send money between African countries, fast and transparently.",
          variant: AfricaCorridorVariant.africaToAfrica,
          allowedDestinations: kLiveEversendCorridors,
        );
      case 3:
        return QuickTransferScreen(user: widget.user, userAuthKey: widget.userAuthKey);
      case 4:
        return ExploreProductScreen(user: widget.user, userAuthKey: widget.userAuthKey);
      case 5:
        return GiftsScreen(user: widget.user, userAuthKey: widget.userAuthKey);
      case 6:
        return AfricaCorridorScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          title: "United States → Africa",
          subtitle: "Send money from the United States to family and friends across Africa.",
          variant: AfricaCorridorVariant.diaspora,
          initialSourceCurrency: 'USD',
          lockSourceCurrency: true,
          allowedDestinations: kLiveEversendCorridors,
        );
      case 7:
        return AfricaCorridorScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          title: "Europe → Africa",
          subtitle: "Send money from Europe to family and friends across Africa.",
          variant: AfricaCorridorVariant.diaspora,
          initialSourceCurrency: 'EUR',
          lockSourceCurrency: true,
          allowedDestinations: kLiveEversendCorridors,
        );
      case 8:
        return GlobalBankTransferScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          initialSourceCurrency: 'XAF',
          initialDestination: kUnitedStatesPayoutCountries.first,
          lockSourceCurrency: true,
          allowedDestinations: kUnitedStatesPayoutCountries,
        );
      case 9:
        return GlobalBankTransferScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          initialSourceCurrency: 'XAF',
          initialDestination: kEuropeanBankPayoutCountries.first,
          lockSourceCurrency: true,
          allowedDestinations: kEuropeanBankPayoutCountries,
        );
      case 10:
        return GlobalBankTransferScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          initialSourceCurrency: 'USD',
          initialDestination: kEuropeanBankPayoutCountries.first,
          lockSourceCurrency: true,
          allowedDestinations: kEuropeanBankPayoutCountries,
        );
      case 11:
        return GlobalBankTransferScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          initialSourceCurrency: 'EUR',
          initialDestination: kUnitedStatesPayoutCountries.first,
          lockSourceCurrency: true,
          allowedDestinations: kUnitedStatesPayoutCountries,
        );
      default:
        return AfricaCorridorScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          title: "Africa to Africa",
          subtitle: "Send money between African countries, fast and transparently.",
          variant: AfricaCorridorVariant.africaToAfrica,
        );
    }
  }
}

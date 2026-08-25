import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/african_country_data.dart';
import 'package:dutch_remit/utilities/slide_right_route.dart';
import 'package:dutch_remit/screens/africa_corridor_screen.dart';

class _QuickPair {
  final String flag;
  final String country;
  final String currencyCode;
  final double rateToDestination;
  const _QuickPair(this.flag, this.country, this.currencyCode, this.rateToDestination);
}

/// The current "you're sending to" destination for this quick-transfer
/// list. Defaults to Cameroon (from the shared kAfricanCountries data),
/// but any African country works the same way.
final AfricanCountryInfo _kDefaultDestination =
    kAfricanCountries.firstWhere((c) => c.countryName == 'Cameroon');

/// ~15 popular sending-country pairs people actually move money along,
/// and back — matching the reference "Where are you sending from?"
/// list (country, live rate, Momo/Wallet payout chips, ~1 min delivery).
const List<_QuickPair> _kQuickPairs = [
  _QuickPair('🇫🇷', 'France', 'EUR', 663.1),
  _QuickPair('🇳🇬', 'Nigeria', 'NGN', 0.4137),
  _QuickPair('🇬🇭', 'Ghana', 'GHS', 49.17),
  _QuickPair('🇰🇪', 'Kenya', 'KES', 4.72),
  _QuickPair('🇬🇧', 'United Kingdom', 'GBP', 752.1),
  _QuickPair('🇿🇲', 'Zambia', 'ZMW', 30.5),
  _QuickPair('🇸🇳', 'Senegal', 'XOF', 0.9975),
  _QuickPair('🇧🇫', 'Burkina Faso', 'XOF', 0.9975),
  _QuickPair('🇺🇸', 'United States', 'USD', 610.4),
  _QuickPair('🇨🇮', "Côte d'Ivoire", 'XOF', 0.9975),
  _QuickPair('🇿🇦', 'South Africa', 'ZAR', 33.9),
  _QuickPair('🇷🇼', 'Rwanda', 'RWF', 0.44),
  _QuickPair('🇹🇿', 'Tanzania', 'TZS', 0.235),
  _QuickPair('🇺🇬', 'Uganda', 'UGX', 0.155),
  _QuickPair('🇨🇦', 'Canada', 'CAD', 450.2),
];

class QuickTransferScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  const QuickTransferScreen({Key? key, required this.user, this.userAuthKey}) : super(key: key);

  @override
  State<QuickTransferScreen> createState() => _QuickTransferScreenState();
}

class _QuickTransferScreenState extends State<QuickTransferScreen> {
  AfricanCountryInfo _destination = _kDefaultDestination;

  void _openCorridor(_QuickPair pair) {
    // Every pair actually routes somewhere real: it opens the
    // Africa-to-Africa (or Diaspora, when the source isn't African)
    // quote screen pre-filled with the tapped source and the current
    // destination, rather than sitting there inert.
    //
    // AfricaCorridorScreen's build() returns bare content (no Scaffold
    // of its own — it's designed to be embedded inside a parent
    // Scaffold, like SendAbroadHubScreen's tabs do). Pushing it
    // directly as a route without one meant no Material ancestor for
    // its buttons ("No Material widget found"), no back button, and
    // content colliding with the status bar — wrap it here exactly
    // like explore_product_screen.dart already does.
    final isAfricanSource = kLiveEversendCorridors.any((c) => c.currencyCode == pair.currencyCode);
    final title = "${pair.country} → ${_destination.countryName}";
    Navigator.push(
      context,
      SlideRightRoute(
        page: Scaffold(
          backgroundColor: AppColors.scaffold,
          appBar: AppBar(
            title: Text(title,
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 17)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: AppColors.ink,
          ),
          body: SafeArea(
            child: AfricaCorridorScreen(
              user: widget.user,
              userAuthKey: widget.userAuthKey,
              title: title,
              subtitle: "Sending from ${pair.country} to ${_destination.countryName}.",
              variant: isAfricanSource
                  ? AfricaCorridorVariant.africaToAfrica
                  : AfricaCorridorVariant.diaspora,
              initialDestination: _destination,
              initialSourceCurrency: isAfricanSource ? 'USD' : pair.currencyCode,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _changeDestination() async {
    final picked = await showModalBottomSheet<AfricanCountryInfo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text("Sending to",
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: kLiveEversendCorridors.length,
                  itemBuilder: (context, index) {
                    final c = kLiveEversendCorridors[index];
                    return ListTile(
                      leading: Text(c.flagEmoji, style: TextStyle(fontSize: 22)),
                      title: Text(c.countryName,
                          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                      subtitle: Text(c.currencyCode, style: TextStyle(color: AppColors.textMuted)),
                      onTap: () => Navigator.of(sheetContext).pop(c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _destination = picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text("Where are you sending from?",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text("Rates updated in the last 30 min",
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.success)),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _changeDestination,
          child: Row(
            children: [
              Text("Sending to ${_destination.flagEmoji} ${_destination.countryName}",
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, decoration: TextDecoration.underline)),
              const SizedBox(width: 4),
              Icon(Icons.edit_outlined, size: 13, color: AppColors.textMuted),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._kQuickPairs.map((pair) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () => _openCorridor(pair),
                borderRadius: BorderRadius.circular(AppRadii.lg),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(pair.flag, style: TextStyle(fontSize: 20)),
                              const SizedBox(width: 6),
                              Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.textMuted),
                              const SizedBox(width: 6),
                              Text(_destination.flagEmoji, style: TextStyle(fontSize: 20)),
                            ],
                          ),
                          Text("${pair.currencyCode} → ${_destination.currencyCode}",
                              style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontFamily: 'monospace')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text("From ${pair.country}",
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink)),
                      const SizedBox(height: 4),
                      Text("1 ${pair.currencyCode} = ${pair.rateToDestination} ${_destination.currencyCode}",
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _chip("Momo"),
                          const SizedBox(width: 8),
                          _chip("Wallet"),
                          const Spacer(),
                          Text("~1 min", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.success)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _openCorridor(pair),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
                          ),
                          child: Text("Continue",
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )),
        const SizedBox(height: 4),
        Text("Delivery times are 90-day medians from real transfers. Rates include Dutch Remit's fee.",
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4)),
      ],
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.pill)),
        child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
      );
}

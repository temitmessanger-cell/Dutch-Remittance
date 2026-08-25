import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// A small pill showing one of the flat-fee tiers Dutch Remit charges,
/// e.g. "$0.80", "$1-2", "$10".
class FeeTiersRow extends StatelessWidget {
  const FeeTiersRow({Key? key}) : super(key: key);

  static const List<String> _tiers = ["\$0.80", "\$1 - \$2", "\$10"];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.payments_outlined, size: 16, color: AppColors.primary),
          const SizedBox(width: 10),
          Text("Transfer fees",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const Spacer(),
          Wrap(
            spacing: 6,
            children: _tiers
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(t,
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// "Instant - 1 min to 1 day" delivery-time strip.
class DeliveryTimeRow extends StatelessWidget {
  final String range;
  const DeliveryTimeRow({Key? key, this.range = "Instant · 1 min to 1 day"}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, size: 17, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text("Delivery time: $range",
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.success)),
          ),
        ],
      ),
    );
  }
}

/// The row of short trust badges — "Live exchange rate", "Fees
/// included", "Mobile money & bank", "Arrives in seconds", "Cheapest
/// fees" — used under the Global Transfer quote card.
class TrustBadgesWrap extends StatelessWidget {
  final List<String> badges;
  const TrustBadgesWrap({Key? key, required this.badges}) : super(key: key);

  static const List<IconData> _icons = [
    Icons.show_chart_rounded,
    Icons.verified_outlined,
    Icons.smartphone_rounded,
    Icons.flash_on_rounded,
    Icons.sell_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(badges.length, (i) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icons[i % _icons.length], size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(badges[i],
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink)),
            ],
          ),
        );
      }),
    );
  }
}

/// A labelled "before / after" comparison row, e.g. "Money arrives —
/// Minutes to hours / Seconds to minutes".
class ComparisonFeatureRow extends StatelessWidget {
  final String label;
  final String value;
  const ComparisonFeatureRow({Key? key, required this.label, required this.value}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                      text: "$label: ",
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  TextSpan(
                      text: value,
                      style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

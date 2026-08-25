import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/currency_country_data.dart';

/// Bottom sheet for picking a currency/country, used for both the "You
/// send" and "They get" pickers in the international transfer flow.
Future<String?> showCurrencyPicker(
    BuildContext context, {required String currentCode}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
    builder: (context) => _CurrencyPickerSheet(currentCode: currentCode),
  );
}

class _CurrencyPickerSheet extends StatefulWidget {
  final String currentCode;
  const _CurrencyPickerSheet({required this.currentCode});

  @override
  State<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<_CurrencyPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = kSupportedCurrencyCountries.where((c) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return c.currencyCode.toLowerCase().contains(q) ||
          c.currencyName.toLowerCase().contains(q) ||
          c.countryName.toLowerCase().contains(q);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Text("Select currency",
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                    const Spacer(),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded,
                            color: AppColors.textMuted, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: "Search currency or country",
                    prefixIcon: Icon(Icons.search_rounded,
                        color: AppColors.textMuted, size: 20),
                    filled: true,
                    fillColor: AppColors.surfaceAlt,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final c = filtered[index];
                    final bool isSelected = c.currencyCode == widget.currentCode;
                    return ListTile(
                      onTap: () => Navigator.of(context).pop(c.currencyCode),
                      leading: Text(c.flagEmoji, style: TextStyle(fontSize: 26)),
                      title: Text("${c.currencyCode} — ${c.currencyName}",
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                              fontSize: 15)),
                      subtitle: Text(c.countryName,
                          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!c.hasLiveRate)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: AppColors.surfaceAlt,
                                  borderRadius: BorderRadius.circular(AppRadii.pill)),
                              child: Text("Rate at delivery",
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                            ),
                          if (isSelected)
                            Icon(Icons.check_circle_rounded,
                                color: AppColors.primary, size: 20),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

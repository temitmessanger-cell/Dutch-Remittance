import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/african_country_data.dart';

Future<AfricanCountryInfo?> showAfricanCountryPicker(
    BuildContext context, {required String currentCountry, bool onlyLiveCorridors = false}) {
  return showModalBottomSheet<AfricanCountryInfo>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
    builder: (context) => _AfricanCountryPickerSheet(
        currentCountry: currentCountry, onlyLiveCorridors: onlyLiveCorridors),
  );
}

class _AfricanCountryPickerSheet extends StatefulWidget {
  final String currentCountry;
  final bool onlyLiveCorridors;
  const _AfricanCountryPickerSheet(
      {required this.currentCountry, this.onlyLiveCorridors = false});

  @override
  State<_AfricanCountryPickerSheet> createState() => _AfricanCountryPickerSheetState();
}

class _AfricanCountryPickerSheetState extends State<_AfricanCountryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final baseList = widget.onlyLiveCorridors ? kLiveEversendCorridors : kAfricanCountries;
    final filtered = baseList.where((c) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return c.countryName.toLowerCase().contains(q) ||
          c.currencyCode.toLowerCase().contains(q);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Text("Choose country",
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    const Spacer(),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded, color: AppColors.textMuted, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: "Search country or currency",
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
                    filled: true,
                    fillColor: AppColors.surfaceAlt,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide.none),
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
                    final bool isSelected = c.countryName == widget.currentCountry;
                    return ListTile(
                      onTap: () => Navigator.of(context).pop(c),
                      leading: Text(c.flagEmoji, style: TextStyle(fontSize: 26)),
                      title: Text(c.countryName,
                          style: TextStyle(
                              fontWeight: FontWeight.w600, color: AppColors.ink, fontSize: 15)),
                      subtitle: Text(
                        c.hasLiveRate
                            ? "${c.currencyCode} — live rate available"
                            : c.currencyCode,
                        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
                          : null,
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/dial_code_data.dart';

/// A phone number field with a real country-code selector — tap the
/// flag/dial-code pill to pick a country, then type the local number.
/// The `+` prefix and country code are always inserted automatically;
/// the caller never has to remember to prepend one, and the number
/// this field reports (via [onChanged] / [fullNumber]) is always a
/// complete, correctly-prefixed E.164-style string like "+237650..." .
///
/// Used across every screen that collects a phone number (deposit,
/// withdrawal, send-abroad recipient fields, card verification,
/// contacts) so the "always show +country code" requirement is one
/// widget to get right, not seven separate ad-hoc text fields.
class PhoneNumberField extends StatefulWidget {
  /// Initial ISO alpha-2 country code for the picker (e.g. 'CM').
  /// Defaults to Cameroon, the app's home market.
  final String initialCountryCode;

  /// Called with the full, prefixed number every time it changes —
  /// e.g. "+237650112233". This is what callers should send to the
  /// backend, never the raw local-number text alone.
  final ValueChanged<String> onChanged;

  final String? hintText;
  final TextEditingController? controller;

  const PhoneNumberField({
    Key? key,
    this.initialCountryCode = 'CM',
    required this.onChanged,
    this.hintText,
    this.controller,
  }) : super(key: key);

  @override
  State<PhoneNumberField> createState() => _PhoneNumberFieldState();
}

class _PhoneNumberFieldState extends State<PhoneNumberField> {
  late DialCodeInfo _selectedDialCode;
  late final TextEditingController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _selectedDialCode = dialCodeForCountry(widget.initialCountryCode);
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_notifyChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_notifyChange);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _notifyChange() {
    final local = _controller.text.trim();
    widget.onChanged(local.isEmpty ? '' : '${_selectedDialCode.dialCode}$local');
  }

  /// The current full, prefixed number — useful for callers that
  /// don't want to track onChanged state themselves.
  String get fullNumber {
    final local = _controller.text.trim();
    return local.isEmpty ? '' : '${_selectedDialCode.dialCode}$local';
  }

  void _pickCountry() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text("Country code",
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink)),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: kDialCodes.length,
                  itemBuilder: (context, index) {
                    final d = kDialCodes[index];
                    final bool isSelected = d.countryCode == _selectedDialCode.countryCode;
                    return ListTile(
                      leading: Text(d.flagEmoji, style: const TextStyle(fontSize: 22)),
                      title: Text(d.countryName,
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(d.dialCode,
                              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                          ],
                        ],
                      ),
                      onTap: () {
                        setState(() => _selectedDialCode = d);
                        Navigator.of(sheetContext).pop();
                        _notifyChange();
                      },
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

  @override
  Widget build(BuildContext context) {
    return Row(
      // FIX: crossAxisAlignment.stretch on a Row stretches every
      // child to fill unbounded vertical space in the cross axis —
      // with no explicit height on the InkWell/TextField below, this
      // made the whole field expand to fill all remaining space in
      // whatever scrollable parent it sat in, pushing every field
      // below it off-screen and making the page scroll seem
      // infinite. That's exactly the bug reported: missing continue
      // buttons, missing fields below, and endless scroll on every
      // screen this widget was added to. Fixed: a normal (default)
      // crossAxisAlignment, with each child given a real, bounded
      // height via SizedBox instead of letting the Row's stretch
      // behavior improvise one.
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 52,
          child: InkWell(
            onTap: _pickCountry,
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_selectedDialCode.flagEmoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(_selectedDialCode.dialCode,
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14)),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 52,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceAlt,
                hintText: widget.hintText ?? "Phone number",
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadii.md)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary, width: 1.6),
                    borderRadius: BorderRadius.circular(AppRadii.md)),
                border: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadii.md)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

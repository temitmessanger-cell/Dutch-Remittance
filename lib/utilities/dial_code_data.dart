/// Country calling codes for the phone-number country picker used
/// across every screen that collects a phone number (deposit,
/// withdrawal, send-abroad recipient fields, card verification,
/// contacts). Covers every country in Backend/src/corridors.js's
/// EVERSEND_PAYOUT_COUNTRIES plus a handful of other common countries
/// so the picker isn't limited to payout destinations only — a user
/// might reasonably have a phone number from a country their wallet
/// doesn't yet support sending to.
class DialCodeInfo {
  final String countryCode; // ISO 3166-1 alpha-2
  final String countryName;
  final String dialCode; // Always starts with '+'
  final String flagEmoji;

  const DialCodeInfo({
    required this.countryCode,
    required this.countryName,
    required this.dialCode,
    required this.flagEmoji,
  });
}

const List<DialCodeInfo> kDialCodes = [
  // Africa — matches corridors.js's confirmed payout countries.
  DialCodeInfo(countryCode: 'CM', countryName: 'Cameroon', dialCode: '+237', flagEmoji: '🇨🇲'),
  DialCodeInfo(countryCode: 'NG', countryName: 'Nigeria', dialCode: '+234', flagEmoji: '🇳🇬'),
  DialCodeInfo(countryCode: 'KE', countryName: 'Kenya', dialCode: '+254', flagEmoji: '🇰🇪'),
  DialCodeInfo(countryCode: 'GH', countryName: 'Ghana', dialCode: '+233', flagEmoji: '🇬🇭'),
  DialCodeInfo(countryCode: 'UG', countryName: 'Uganda', dialCode: '+256', flagEmoji: '🇺🇬'),
  DialCodeInfo(countryCode: 'TZ', countryName: 'Tanzania', dialCode: '+255', flagEmoji: '🇹🇿'),
  DialCodeInfo(countryCode: 'RW', countryName: 'Rwanda', dialCode: '+250', flagEmoji: '🇷🇼'),
  DialCodeInfo(countryCode: 'ZM', countryName: 'Zambia', dialCode: '+260', flagEmoji: '🇿🇲'),
  DialCodeInfo(countryCode: 'SN', countryName: 'Senegal', dialCode: '+221', flagEmoji: '🇸🇳'),
  DialCodeInfo(countryCode: 'CI', countryName: "Côte d'Ivoire", dialCode: '+225', flagEmoji: '🇨🇮'),
  DialCodeInfo(countryCode: 'BJ', countryName: 'Benin', dialCode: '+229', flagEmoji: '🇧🇯'),
  DialCodeInfo(countryCode: 'BF', countryName: 'Burkina Faso', dialCode: '+226', flagEmoji: '🇧🇫'),
  DialCodeInfo(countryCode: 'GA', countryName: 'Gabon', dialCode: '+241', flagEmoji: '🇬🇦'),
  DialCodeInfo(countryCode: 'GQ', countryName: 'Equatorial Guinea', dialCode: '+240', flagEmoji: '🇬🇶'),
  DialCodeInfo(countryCode: 'GW', countryName: 'Guinea-Bissau', dialCode: '+245', flagEmoji: '🇬🇼'),
  DialCodeInfo(countryCode: 'ML', countryName: 'Mali', dialCode: '+223', flagEmoji: '🇲🇱'),
  DialCodeInfo(countryCode: 'NE', countryName: 'Niger', dialCode: '+227', flagEmoji: '🇳🇪'),
  DialCodeInfo(countryCode: 'TD', countryName: 'Chad', dialCode: '+235', flagEmoji: '🇹🇩'),
  DialCodeInfo(countryCode: 'TG', countryName: 'Togo', dialCode: '+228', flagEmoji: '🇹🇬'),
  DialCodeInfo(countryCode: 'ZA', countryName: 'South Africa', dialCode: '+27', flagEmoji: '🇿🇦'),

  // Europe — matches corridors.js's confirmed EUR/GBP payout countries.
  DialCodeInfo(countryCode: 'AT', countryName: 'Austria', dialCode: '+43', flagEmoji: '🇦🇹'),
  DialCodeInfo(countryCode: 'BE', countryName: 'Belgium', dialCode: '+32', flagEmoji: '🇧🇪'),
  DialCodeInfo(countryCode: 'BG', countryName: 'Bulgaria', dialCode: '+359', flagEmoji: '🇧🇬'),
  DialCodeInfo(countryCode: 'CY', countryName: 'Cyprus', dialCode: '+357', flagEmoji: '🇨🇾'),
  DialCodeInfo(countryCode: 'DE', countryName: 'Germany', dialCode: '+49', flagEmoji: '🇩🇪'),
  DialCodeInfo(countryCode: 'EE', countryName: 'Estonia', dialCode: '+372', flagEmoji: '🇪🇪'),
  DialCodeInfo(countryCode: 'ES', countryName: 'Spain', dialCode: '+34', flagEmoji: '🇪🇸'),
  DialCodeInfo(countryCode: 'FI', countryName: 'Finland', dialCode: '+358', flagEmoji: '🇫🇮'),
  DialCodeInfo(countryCode: 'FR', countryName: 'France', dialCode: '+33', flagEmoji: '🇫🇷'),
  DialCodeInfo(countryCode: 'GB', countryName: 'United Kingdom', dialCode: '+44', flagEmoji: '🇬🇧'),
  DialCodeInfo(countryCode: 'GR', countryName: 'Greece', dialCode: '+30', flagEmoji: '🇬🇷'),
  DialCodeInfo(countryCode: 'HR', countryName: 'Croatia', dialCode: '+385', flagEmoji: '🇭🇷'),
  DialCodeInfo(countryCode: 'IE', countryName: 'Ireland', dialCode: '+353', flagEmoji: '🇮🇪'),
  DialCodeInfo(countryCode: 'IT', countryName: 'Italy', dialCode: '+39', flagEmoji: '🇮🇹'),
  DialCodeInfo(countryCode: 'LT', countryName: 'Lithuania', dialCode: '+370', flagEmoji: '🇱🇹'),
  DialCodeInfo(countryCode: 'LU', countryName: 'Luxembourg', dialCode: '+352', flagEmoji: '🇱🇺'),
  DialCodeInfo(countryCode: 'LV', countryName: 'Latvia', dialCode: '+371', flagEmoji: '🇱🇻'),
  DialCodeInfo(countryCode: 'MT', countryName: 'Malta', dialCode: '+356', flagEmoji: '🇲🇹'),
  DialCodeInfo(countryCode: 'NL', countryName: 'Netherlands', dialCode: '+31', flagEmoji: '🇳🇱'),
  DialCodeInfo(countryCode: 'PT', countryName: 'Portugal', dialCode: '+351', flagEmoji: '🇵🇹'),
  DialCodeInfo(countryCode: 'SI', countryName: 'Slovenia', dialCode: '+386', flagEmoji: '🇸🇮'),
  DialCodeInfo(countryCode: 'SK', countryName: 'Slovakia', dialCode: '+421', flagEmoji: '🇸🇰'),

  // North America.
  DialCodeInfo(countryCode: 'US', countryName: 'United States', dialCode: '+1', flagEmoji: '🇺🇸'),
  DialCodeInfo(countryCode: 'CA', countryName: 'Canada', dialCode: '+1', flagEmoji: '🇨🇦'),

  // Common non-payout countries a user's own phone number might be
  // from, even if the wallet can't send there yet — UAE and India in
  // particular, given the "Europe, UAE, Asia" positioning elsewhere
  // in this app.
  DialCodeInfo(countryCode: 'AE', countryName: 'United Arab Emirates', dialCode: '+971', flagEmoji: '🇦🇪'),
  DialCodeInfo(countryCode: 'IN', countryName: 'India', dialCode: '+91', flagEmoji: '🇮🇳'),
  DialCodeInfo(countryCode: 'CN', countryName: 'China', dialCode: '+86', flagEmoji: '🇨🇳'),
  DialCodeInfo(countryCode: 'TR', countryName: 'Turkey', dialCode: '+90', flagEmoji: '🇹🇷'),
];

/// Looks up the DialCodeInfo for a given ISO alpha-2 country code,
/// falling back to Cameroon (the app's home market) if not found —
/// never returns null, so a caller always gets a sensible default
/// rather than having to null-check everywhere.
DialCodeInfo dialCodeForCountry(String countryCode) {
  return kDialCodes.firstWhere(
    (d) => d.countryCode == countryCode.toUpperCase(),
    orElse: () => kDialCodes.first,
  );
}

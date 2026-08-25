/// Bank-transfer payout destinations — mirrors
/// Backend/src/corridors.js's EVERSEND_PAYOUT_COUNTRIES filtered to
/// countries with a real `bank` payout method (the African
/// mobile-money-only corridors already have their own flow in
/// AfricaCorridorScreen / MobileMoneyWithdrawalScreen). Pulled live
/// from Eversend's own GET /v1/payouts/countries (2026-08-25) — the
/// definitive source, since their public docs/app lag what's actually
/// enabled. Re-pull that endpoint periodically; Eversend adds/removes
/// corridors without notice.
class PayoutCountryInfo {
  final String countryName;
  final String countryCode;
  final String currencyCode;
  final String flagEmoji;

  const PayoutCountryInfo({
    required this.countryName,
    required this.countryCode,
    required this.currencyCode,
    required this.flagEmoji,
  });
}

const List<PayoutCountryInfo> kBankPayoutCountries = [
  PayoutCountryInfo(countryName: 'Austria', countryCode: 'AT', currencyCode: 'EUR', flagEmoji: '🇦🇹'),
  PayoutCountryInfo(countryName: 'Belgium', countryCode: 'BE', currencyCode: 'EUR', flagEmoji: '🇧🇪'),
  PayoutCountryInfo(countryName: 'Cyprus', countryCode: 'CY', currencyCode: 'EUR', flagEmoji: '🇨🇾'),
  PayoutCountryInfo(countryName: 'Germany', countryCode: 'DE', currencyCode: 'EUR', flagEmoji: '🇩🇪'),
  PayoutCountryInfo(countryName: 'Estonia', countryCode: 'EE', currencyCode: 'EUR', flagEmoji: '🇪🇪'),
  PayoutCountryInfo(countryName: 'Finland', countryCode: 'FI', currencyCode: 'EUR', flagEmoji: '🇫🇮'),
  PayoutCountryInfo(countryName: 'France', countryCode: 'FR', currencyCode: 'EUR', flagEmoji: '🇫🇷'),
  PayoutCountryInfo(countryName: 'United Kingdom', countryCode: 'GB', currencyCode: 'GBP', flagEmoji: '🇬🇧'),
  PayoutCountryInfo(countryName: 'Ghana', countryCode: 'GH', currencyCode: 'GHS', flagEmoji: '🇬🇭'),
  PayoutCountryInfo(countryName: 'Greece', countryCode: 'GR', currencyCode: 'EUR', flagEmoji: '🇬🇷'),
  PayoutCountryInfo(countryName: 'Croatia', countryCode: 'HR', currencyCode: 'EUR', flagEmoji: '🇭🇷'),
  PayoutCountryInfo(countryName: 'Ireland', countryCode: 'IE', currencyCode: 'EUR', flagEmoji: '🇮🇪'),
  PayoutCountryInfo(countryName: 'Italy', countryCode: 'IT', currencyCode: 'EUR', flagEmoji: '🇮🇹'),
  PayoutCountryInfo(countryName: 'Kenya', countryCode: 'KE', currencyCode: 'KES', flagEmoji: '🇰🇪'),
  PayoutCountryInfo(countryName: 'Lithuania', countryCode: 'LT', currencyCode: 'EUR', flagEmoji: '🇱🇹'),
  PayoutCountryInfo(countryName: 'Luxembourg', countryCode: 'LU', currencyCode: 'EUR', flagEmoji: '🇱🇺'),
  PayoutCountryInfo(countryName: 'Latvia', countryCode: 'LV', currencyCode: 'EUR', flagEmoji: '🇱🇻'),
  PayoutCountryInfo(countryName: 'Malta', countryCode: 'MT', currencyCode: 'EUR', flagEmoji: '🇲🇹'),
  PayoutCountryInfo(countryName: 'Nigeria', countryCode: 'NG', currencyCode: 'NGN', flagEmoji: '🇳🇬'),
  PayoutCountryInfo(countryName: 'Netherlands', countryCode: 'NL', currencyCode: 'EUR', flagEmoji: '🇳🇱'),
  PayoutCountryInfo(countryName: 'Portugal', countryCode: 'PT', currencyCode: 'EUR', flagEmoji: '🇵🇹'),
  PayoutCountryInfo(countryName: 'Slovenia', countryCode: 'SI', currencyCode: 'EUR', flagEmoji: '🇸🇮'),
  PayoutCountryInfo(countryName: 'Slovakia', countryCode: 'SK', currencyCode: 'EUR', flagEmoji: '🇸🇰'),
  PayoutCountryInfo(countryName: 'Uganda', countryCode: 'UG', currencyCode: 'UGX', flagEmoji: '🇺🇬'),
  PayoutCountryInfo(countryName: 'United States', countryCode: 'US', currencyCode: 'USD', flagEmoji: '🇺🇸'),
];

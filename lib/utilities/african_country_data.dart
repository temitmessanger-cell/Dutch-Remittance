/// African countries available in the Diaspora-to-Africa and
/// Africa-to-Africa corridors, with their local currency code and
/// whether that currency has a real, live exchange rate available.
///
/// [liveConfirmed] = true means this country appeared in the live
/// Eversend GET /v1/payouts/countries response (tested 2026-09).
/// [isEversendCorridor] = true but [liveConfirmed] = false means the
/// country is inferred from sharing a confirmed currency (XAF/XOF)
/// but hasn't appeared individually in the live API response yet —
/// shown in the UI with a "Coming Soon" tag at the end of the flow.
class AfricanCountryInfo {
  final String countryName;
  final String countryCode;
  final String currencyCode;
  final String currencyName;
  final String flagEmoji;
  final bool hasLiveRate;
  final bool isEversendCorridor;
  /// True only when this country was individually confirmed in the
  /// live Eversend GET /v1/payouts/countries response.
  final bool liveConfirmed;

  const AfricanCountryInfo({
    required this.countryName,
    required this.countryCode,
    required this.currencyCode,
    required this.currencyName,
    required this.flagEmoji,
    required this.hasLiveRate,
    this.isEversendCorridor = false,
    this.liveConfirmed = false,
  });
}

const List<AfricanCountryInfo> kAfricanCountries = [
  // ── Live-confirmed Eversend payout corridors (from GET /v1/payouts/countries, 2026-09) ──
  AfricanCountryInfo(countryName: 'Nigeria',        countryCode: 'NG', currencyCode: 'NGN', currencyName: 'Nigerian Naira',             flagEmoji: '🇳🇬', hasLiveRate: false, isEversendCorridor: true, liveConfirmed: true),
  AfricanCountryInfo(countryName: 'Kenya',          countryCode: 'KE', currencyCode: 'KES', currencyName: 'Kenyan Shilling',            flagEmoji: '🇰🇪', hasLiveRate: false, isEversendCorridor: true, liveConfirmed: true),
  AfricanCountryInfo(countryName: 'Ghana',          countryCode: 'GH', currencyCode: 'GHS', currencyName: 'Ghanaian Cedi',             flagEmoji: '🇬🇭', hasLiveRate: false, isEversendCorridor: true, liveConfirmed: true),
  AfricanCountryInfo(countryName: 'Uganda',         countryCode: 'UG', currencyCode: 'UGX', currencyName: 'Ugandan Shilling',          flagEmoji: '🇺🇬', hasLiveRate: false, isEversendCorridor: true, liveConfirmed: true),
  AfricanCountryInfo(countryName: 'Rwanda',         countryCode: 'RW', currencyCode: 'RWF', currencyName: 'Rwandan Franc',             flagEmoji: '🇷🇼', hasLiveRate: false, isEversendCorridor: true, liveConfirmed: true),
  AfricanCountryInfo(countryName: 'Tanzania',       countryCode: 'TZ', currencyCode: 'TZS', currencyName: 'Tanzanian Shilling',        flagEmoji: '🇹🇿', hasLiveRate: false, isEversendCorridor: true, liveConfirmed: true),
  AfricanCountryInfo(countryName: 'Zambia',         countryCode: 'ZM', currencyCode: 'ZMW', currencyName: 'Zambian Kwacha',            flagEmoji: '🇿🇲', hasLiveRate: false, isEversendCorridor: true, liveConfirmed: true),
  AfricanCountryInfo(countryName: 'Cameroon',       countryCode: 'CM', currencyCode: 'XAF', currencyName: 'Central African CFA Franc', flagEmoji: '🇨🇲', hasLiveRate: false, isEversendCorridor: true, liveConfirmed: true),
  AfricanCountryInfo(countryName: 'Senegal',        countryCode: 'SN', currencyCode: 'XOF', currencyName: 'West African CFA Franc',    flagEmoji: '🇸🇳', hasLiveRate: false, isEversendCorridor: true, liveConfirmed: true),
  AfricanCountryInfo(countryName: "Côte d'Ivoire",  countryCode: 'CI', currencyCode: 'XOF', currencyName: 'West African CFA Franc',    flagEmoji: '🇨🇮', hasLiveRate: false, isEversendCorridor: true, liveConfirmed: true),

  // ── Eversend corridor inferred from shared currency — shown with "Coming Soon" tag ──
  AfricanCountryInfo(countryName: 'Gabon',          countryCode: 'GA', currencyCode: 'XAF', currencyName: 'Central African CFA Franc', flagEmoji: '🇬🇦', hasLiveRate: false, isEversendCorridor: true,  liveConfirmed: false),
  AfricanCountryInfo(countryName: 'Equatorial Guinea', countryCode: 'GQ', currencyCode: 'XAF', currencyName: 'Central African CFA Franc', flagEmoji: '🇬🇶', hasLiveRate: false, isEversendCorridor: true, liveConfirmed: false),
  AfricanCountryInfo(countryName: 'Chad',           countryCode: 'TD', currencyCode: 'XAF', currencyName: 'Central African CFA Franc', flagEmoji: '🇹🇩', hasLiveRate: false, isEversendCorridor: true,  liveConfirmed: false),
  AfricanCountryInfo(countryName: 'Mali',           countryCode: 'ML', currencyCode: 'XOF', currencyName: 'West African CFA Franc',    flagEmoji: '🇲🇱', hasLiveRate: false, isEversendCorridor: true,  liveConfirmed: false),
  AfricanCountryInfo(countryName: 'Togo',           countryCode: 'TG', currencyCode: 'XOF', currencyName: 'West African CFA Franc',    flagEmoji: '🇹🇬', hasLiveRate: false, isEversendCorridor: true,  liveConfirmed: false),
  AfricanCountryInfo(countryName: 'Benin',          countryCode: 'BJ', currencyCode: 'XOF', currencyName: 'West African CFA Franc',    flagEmoji: '🇧🇯', hasLiveRate: false, isEversendCorridor: true,  liveConfirmed: false),
  AfricanCountryInfo(countryName: 'Niger',          countryCode: 'NE', currencyCode: 'XOF', currencyName: 'West African CFA Franc',    flagEmoji: '🇳🇪', hasLiveRate: false, isEversendCorridor: true,  liveConfirmed: false),
  AfricanCountryInfo(countryName: 'Burkina Faso',   countryCode: 'BF', currencyCode: 'XOF', currencyName: 'West African CFA Franc',    flagEmoji: '🇧🇫', hasLiveRate: false, isEversendCorridor: true,  liveConfirmed: false),
  AfricanCountryInfo(countryName: 'Guinea-Bissau',  countryCode: 'GW', currencyCode: 'XOF', currencyName: 'West African CFA Franc',    flagEmoji: '🇬🇼', hasLiveRate: false, isEversendCorridor: true,  liveConfirmed: false),

  // ── Not yet on Eversend — shown for completeness only ──
  AfricanCountryInfo(countryName: 'South Africa',   countryCode: 'ZA', currencyCode: 'ZAR', currencyName: 'South African Rand',        flagEmoji: '🇿🇦', hasLiveRate: true),
  AfricanCountryInfo(countryName: 'Burundi',        countryCode: 'BI', currencyCode: 'BIF', currencyName: 'Burundian Franc',           flagEmoji: '🇧🇮', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'DR Congo',       countryCode: 'CD', currencyCode: 'CDF', currencyName: 'Congolese Franc',           flagEmoji: '🇨🇩', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Congo',          countryCode: 'CG', currencyCode: 'XAF', currencyName: 'Central African CFA Franc', flagEmoji: '🇨🇬', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Central African Republic', countryCode: 'CF', currencyCode: 'XAF', currencyName: 'Central African CFA Franc', flagEmoji: '🇨🇫', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Guinea',         countryCode: 'GN', currencyCode: 'GNF', currencyName: 'Guinean Franc',             flagEmoji: '🇬🇳', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Madagascar',     countryCode: 'MG', currencyCode: 'MGA', currencyName: 'Malagasy Ariary',           flagEmoji: '🇲🇬', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Malawi',         countryCode: 'MW', currencyCode: 'MWK', currencyName: 'Malawian Kwacha',           flagEmoji: '🇲🇼', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Mozambique',     countryCode: 'MZ', currencyCode: 'MZN', currencyName: 'Mozambican Metical',        flagEmoji: '🇲🇿', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Zimbabwe',       countryCode: 'ZW', currencyCode: 'ZWL', currencyName: 'Zimbabwean Dollar',         flagEmoji: '🇿🇼', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Ethiopia',       countryCode: 'ET', currencyCode: 'ETB', currencyName: 'Ethiopian Birr',            flagEmoji: '🇪🇹', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Egypt',          countryCode: 'EG', currencyCode: 'EGP', currencyName: 'Egyptian Pound',            flagEmoji: '🇪🇬', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Morocco',        countryCode: 'MA', currencyCode: 'MAD', currencyName: 'Moroccan Dirham',           flagEmoji: '🇲🇦', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Algeria',        countryCode: 'DZ', currencyCode: 'DZD', currencyName: 'Algerian Dinar',            flagEmoji: '🇩🇿', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Tunisia',        countryCode: 'TN', currencyCode: 'TND', currencyName: 'Tunisian Dinar',            flagEmoji: '🇹🇳', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Botswana',       countryCode: 'BW', currencyCode: 'BWP', currencyName: 'Botswana Pula',             flagEmoji: '🇧🇼', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Namibia',        countryCode: 'NA', currencyCode: 'NAD', currencyName: 'Namibian Dollar',           flagEmoji: '🇳🇦', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Sudan',          countryCode: 'SD', currencyCode: 'SDG', currencyName: 'Sudanese Pound',            flagEmoji: '🇸🇩', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'South Sudan',    countryCode: 'SS', currencyCode: 'SSP', currencyName: 'South Sudanese Pound',      flagEmoji: '🇸🇸', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Somalia',        countryCode: 'SO', currencyCode: 'SOS', currencyName: 'Somali Shilling',           flagEmoji: '🇸🇴', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Eritrea',        countryCode: 'ER', currencyCode: 'ERN', currencyName: 'Eritrean Nakfa',            flagEmoji: '🇪🇷', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Djibouti',       countryCode: 'DJ', currencyCode: 'DJF', currencyName: 'Djiboutian Franc',          flagEmoji: '🇩🇯', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Sierra Leone',   countryCode: 'SL', currencyCode: 'SLL', currencyName: 'Sierra Leonean Leone',      flagEmoji: '🇸🇱', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Liberia',        countryCode: 'LR', currencyCode: 'LRD', currencyName: 'Liberian Dollar',          flagEmoji: '🇱🇷', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'The Gambia',     countryCode: 'GM', currencyCode: 'GMD', currencyName: 'Gambian Dalasi',            flagEmoji: '🇬🇲', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Mauritania',     countryCode: 'MR', currencyCode: 'MRU', currencyName: 'Mauritanian Ouguiya',       flagEmoji: '🇲🇷', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Cape Verde',     countryCode: 'CV', currencyCode: 'CVE', currencyName: 'Cape Verdean Escudo',       flagEmoji: '🇨🇻', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Mauritius',      countryCode: 'MU', currencyCode: 'MUR', currencyName: 'Mauritian Rupee',           flagEmoji: '🇲🇺', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Seychelles',     countryCode: 'SC', currencyCode: 'SCR', currencyName: 'Seychellois Rupee',         flagEmoji: '🇸🇨', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Comoros',        countryCode: 'KM', currencyCode: 'KMF', currencyName: 'Comorian Franc',            flagEmoji: '🇰🇲', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Angola',         countryCode: 'AO', currencyCode: 'AOA', currencyName: 'Angolan Kwanza',            flagEmoji: '🇦🇴', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Lesotho',        countryCode: 'LS', currencyCode: 'LSL', currencyName: 'Lesotho Loti',              flagEmoji: '🇱🇸', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Eswatini',       countryCode: 'SZ', currencyCode: 'SZL', currencyName: 'Swazi Lilangeni',           flagEmoji: '🇸🇿', hasLiveRate: false),
  AfricanCountryInfo(countryName: 'Libya',          countryCode: 'LY', currencyCode: 'LYD', currencyName: 'Libyan Dinar',              flagEmoji: '🇱🇾', hasLiveRate: false),
];

/// Countries individually confirmed live on Eversend's payout API.
/// Use this for any flow that executes a real payout or deposit.
final List<AfricanCountryInfo> kLiveEversendCorridors =
    kAfricanCountries.where((c) => c.liveConfirmed).toList();

/// All Eversend-intended corridors (confirmed + inferred).
/// Use this for country pickers that show the full range with tags.
final List<AfricanCountryInfo> kAllEversendCorridors =
    kAfricanCountries.where((c) => c.isEversendCorridor).toList();

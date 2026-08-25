/// Display metadata (country, flag, full currency name) for currencies
/// the app can show throughout its pickers and quote screens. Kept as
/// plain data rather than fetched from an API since this is reference
/// data that almost never changes and needs to render instantly when
/// a picker opens.
///
/// [hasLiveRate] mirrors the same honest pattern used for African
/// countries in african_country_data.dart: only the ~31 currencies
/// CurrencyConversionService.supportedCurrencies actually prices
/// (via the free Frankfurter/ECB feed) are marked true. Every other
/// currency below is still fully selectable everywhere in the app —
/// for a larger, genuinely useful picker — but the UI shows "Rate
/// shown at delivery" / "No rate available" for it instead of
/// inventing a number, exactly as it already does for most African
/// currencies.
class CurrencyCountryInfo {
  final String currencyCode;
  final String currencyName;
  final String countryName;
  final String flagEmoji;
  final bool hasLiveRate;

  const CurrencyCountryInfo({
    required this.currencyCode,
    required this.currencyName,
    required this.countryName,
    required this.flagEmoji,
    this.hasLiveRate = false,
  });
}

/// 100+ world currencies. The first 31 are the real, working
/// Frankfurter/ECB set (hasLiveRate: true); everything after is
/// selectable for display, routing and quote-building throughout the
/// app, with live pricing shown as soon as a rate source is added.
const List<CurrencyCountryInfo> kSupportedCurrencyCountries = [
  // --- Live-rate currencies (Frankfurter / ECB feed) ---
  CurrencyCountryInfo(currencyCode: 'USD', currencyName: 'US Dollar', countryName: 'United States', flagEmoji: '🇺🇸', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'EUR', currencyName: 'Euro', countryName: 'Eurozone', flagEmoji: '🇪🇺', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'GBP', currencyName: 'British Pound', countryName: 'United Kingdom', flagEmoji: '🇬🇧', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'AUD', currencyName: 'Australian Dollar', countryName: 'Australia', flagEmoji: '🇦🇺', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'BGN', currencyName: 'Bulgarian Lev', countryName: 'Bulgaria', flagEmoji: '🇧🇬', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'BRL', currencyName: 'Brazilian Real', countryName: 'Brazil', flagEmoji: '🇧🇷', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'CAD', currencyName: 'Canadian Dollar', countryName: 'Canada', flagEmoji: '🇨🇦', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'CHF', currencyName: 'Swiss Franc', countryName: 'Switzerland', flagEmoji: '🇨🇭', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'CNY', currencyName: 'Chinese Yuan', countryName: 'China', flagEmoji: '🇨🇳', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'CZK', currencyName: 'Czech Koruna', countryName: 'Czech Republic', flagEmoji: '🇨🇿', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'DKK', currencyName: 'Danish Krone', countryName: 'Denmark', flagEmoji: '🇩🇰', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'HKD', currencyName: 'Hong Kong Dollar', countryName: 'Hong Kong', flagEmoji: '🇭🇰', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'HUF', currencyName: 'Hungarian Forint', countryName: 'Hungary', flagEmoji: '🇭🇺', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'IDR', currencyName: 'Indonesian Rupiah', countryName: 'Indonesia', flagEmoji: '🇮🇩', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'ILS', currencyName: 'Israeli New Shekel', countryName: 'Israel', flagEmoji: '🇮🇱', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'INR', currencyName: 'Indian Rupee', countryName: 'India', flagEmoji: '🇮🇳', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'ISK', currencyName: 'Icelandic Krona', countryName: 'Iceland', flagEmoji: '🇮🇸', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'JPY', currencyName: 'Japanese Yen', countryName: 'Japan', flagEmoji: '🇯🇵', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'KRW', currencyName: 'South Korean Won', countryName: 'South Korea', flagEmoji: '🇰🇷', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'MXN', currencyName: 'Mexican Peso', countryName: 'Mexico', flagEmoji: '🇲🇽', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'MYR', currencyName: 'Malaysian Ringgit', countryName: 'Malaysia', flagEmoji: '🇲🇾', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'NOK', currencyName: 'Norwegian Krone', countryName: 'Norway', flagEmoji: '🇳🇴', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'NZD', currencyName: 'New Zealand Dollar', countryName: 'New Zealand', flagEmoji: '🇳🇿', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'PHP', currencyName: 'Philippine Peso', countryName: 'Philippines', flagEmoji: '🇵🇭', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'PLN', currencyName: 'Polish Zloty', countryName: 'Poland', flagEmoji: '🇵🇱', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'RON', currencyName: 'Romanian Leu', countryName: 'Romania', flagEmoji: '🇷🇴', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'SEK', currencyName: 'Swedish Krona', countryName: 'Sweden', flagEmoji: '🇸🇪', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'SGD', currencyName: 'Singapore Dollar', countryName: 'Singapore', flagEmoji: '🇸🇬', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'THB', currencyName: 'Thai Baht', countryName: 'Thailand', flagEmoji: '🇹🇭', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'TRY', currencyName: 'Turkish Lira', countryName: 'Turkey', flagEmoji: '🇹🇷', hasLiveRate: true),
  CurrencyCountryInfo(currencyCode: 'ZAR', currencyName: 'South African Rand', countryName: 'South Africa', flagEmoji: '🇿🇦', hasLiveRate: true),

  // --- Additional currencies (selectable everywhere; rate shown at delivery) ---
  CurrencyCountryInfo(currencyCode: 'AED', currencyName: 'UAE Dirham', countryName: 'United Arab Emirates', flagEmoji: '🇦🇪'),
  CurrencyCountryInfo(currencyCode: 'AFN', currencyName: 'Afghan Afghani', countryName: 'Afghanistan', flagEmoji: '🇦🇫'),
  CurrencyCountryInfo(currencyCode: 'ALL', currencyName: 'Albanian Lek', countryName: 'Albania', flagEmoji: '🇦🇱'),
  CurrencyCountryInfo(currencyCode: 'AMD', currencyName: 'Armenian Dram', countryName: 'Armenia', flagEmoji: '🇦🇲'),
  CurrencyCountryInfo(currencyCode: 'ARS', currencyName: 'Argentine Peso', countryName: 'Argentina', flagEmoji: '🇦🇷'),
  CurrencyCountryInfo(currencyCode: 'AZN', currencyName: 'Azerbaijani Manat', countryName: 'Azerbaijan', flagEmoji: '🇦🇿'),
  CurrencyCountryInfo(currencyCode: 'BAM', currencyName: 'Bosnia-Herzegovina Mark', countryName: 'Bosnia and Herzegovina', flagEmoji: '🇧🇦'),
  CurrencyCountryInfo(currencyCode: 'BDT', currencyName: 'Bangladeshi Taka', countryName: 'Bangladesh', flagEmoji: '🇧🇩'),
  CurrencyCountryInfo(currencyCode: 'BHD', currencyName: 'Bahraini Dinar', countryName: 'Bahrain', flagEmoji: '🇧🇭'),
  CurrencyCountryInfo(currencyCode: 'BND', currencyName: 'Brunei Dollar', countryName: 'Brunei', flagEmoji: '🇧🇳'),
  CurrencyCountryInfo(currencyCode: 'BOB', currencyName: 'Bolivian Boliviano', countryName: 'Bolivia', flagEmoji: '🇧🇴'),
  CurrencyCountryInfo(currencyCode: 'BYN', currencyName: 'Belarusian Ruble', countryName: 'Belarus', flagEmoji: '🇧🇾'),
  CurrencyCountryInfo(currencyCode: 'CLP', currencyName: 'Chilean Peso', countryName: 'Chile', flagEmoji: '🇨🇱'),
  CurrencyCountryInfo(currencyCode: 'COP', currencyName: 'Colombian Peso', countryName: 'Colombia', flagEmoji: '🇨🇴'),
  CurrencyCountryInfo(currencyCode: 'CRC', currencyName: 'Costa Rican Colon', countryName: 'Costa Rica', flagEmoji: '🇨🇷'),
  CurrencyCountryInfo(currencyCode: 'CUP', currencyName: 'Cuban Peso', countryName: 'Cuba', flagEmoji: '🇨🇺'),
  CurrencyCountryInfo(currencyCode: 'DOP', currencyName: 'Dominican Peso', countryName: 'Dominican Republic', flagEmoji: '🇩🇴'),
  CurrencyCountryInfo(currencyCode: 'DZD', currencyName: 'Algerian Dinar', countryName: 'Algeria', flagEmoji: '🇩🇿'),
  CurrencyCountryInfo(currencyCode: 'EGP', currencyName: 'Egyptian Pound', countryName: 'Egypt', flagEmoji: '🇪🇬'),
  CurrencyCountryInfo(currencyCode: 'FJD', currencyName: 'Fijian Dollar', countryName: 'Fiji', flagEmoji: '🇫🇯'),
  CurrencyCountryInfo(currencyCode: 'GEL', currencyName: 'Georgian Lari', countryName: 'Georgia', flagEmoji: '🇬🇪'),
  CurrencyCountryInfo(currencyCode: 'GTQ', currencyName: 'Guatemalan Quetzal', countryName: 'Guatemala', flagEmoji: '🇬🇹'),
  CurrencyCountryInfo(currencyCode: 'HNL', currencyName: 'Honduran Lempira', countryName: 'Honduras', flagEmoji: '🇭🇳'),
  CurrencyCountryInfo(currencyCode: 'HRK', currencyName: 'Croatian Kuna', countryName: 'Croatia', flagEmoji: '🇭🇷'),
  CurrencyCountryInfo(currencyCode: 'IQD', currencyName: 'Iraqi Dinar', countryName: 'Iraq', flagEmoji: '🇮🇶'),
  CurrencyCountryInfo(currencyCode: 'IRR', currencyName: 'Iranian Rial', countryName: 'Iran', flagEmoji: '🇮🇷'),
  CurrencyCountryInfo(currencyCode: 'JMD', currencyName: 'Jamaican Dollar', countryName: 'Jamaica', flagEmoji: '🇯🇲'),
  CurrencyCountryInfo(currencyCode: 'JOD', currencyName: 'Jordanian Dinar', countryName: 'Jordan', flagEmoji: '🇯🇴'),
  CurrencyCountryInfo(currencyCode: 'KHR', currencyName: 'Cambodian Riel', countryName: 'Cambodia', flagEmoji: '🇰🇭'),
  CurrencyCountryInfo(currencyCode: 'KWD', currencyName: 'Kuwaiti Dinar', countryName: 'Kuwait', flagEmoji: '🇰🇼'),
  CurrencyCountryInfo(currencyCode: 'KZT', currencyName: 'Kazakhstani Tenge', countryName: 'Kazakhstan', flagEmoji: '🇰🇿'),
  CurrencyCountryInfo(currencyCode: 'LAK', currencyName: 'Lao Kip', countryName: 'Laos', flagEmoji: '🇱🇦'),
  CurrencyCountryInfo(currencyCode: 'LBP', currencyName: 'Lebanese Pound', countryName: 'Lebanon', flagEmoji: '🇱🇧'),
  CurrencyCountryInfo(currencyCode: 'LKR', currencyName: 'Sri Lankan Rupee', countryName: 'Sri Lanka', flagEmoji: '🇱🇰'),
  CurrencyCountryInfo(currencyCode: 'MAD', currencyName: 'Moroccan Dirham', countryName: 'Morocco', flagEmoji: '🇲🇦'),
  CurrencyCountryInfo(currencyCode: 'MDL', currencyName: 'Moldovan Leu', countryName: 'Moldova', flagEmoji: '🇲🇩'),
  CurrencyCountryInfo(currencyCode: 'MMK', currencyName: 'Myanmar Kyat', countryName: 'Myanmar', flagEmoji: '🇲🇲'),
  CurrencyCountryInfo(currencyCode: 'MNT', currencyName: 'Mongolian Tugrik', countryName: 'Mongolia', flagEmoji: '🇲🇳'),
  CurrencyCountryInfo(currencyCode: 'MOP', currencyName: 'Macanese Pataca', countryName: 'Macau', flagEmoji: '🇲🇴'),
  CurrencyCountryInfo(currencyCode: 'MUR', currencyName: 'Mauritian Rupee', countryName: 'Mauritius', flagEmoji: '🇲🇺'),
  CurrencyCountryInfo(currencyCode: 'NGN', currencyName: 'Nigerian Naira', countryName: 'Nigeria', flagEmoji: '🇳🇬'),
  CurrencyCountryInfo(currencyCode: 'NIO', currencyName: 'Nicaraguan Cordoba', countryName: 'Nicaragua', flagEmoji: '🇳🇮'),
  CurrencyCountryInfo(currencyCode: 'NPR', currencyName: 'Nepalese Rupee', countryName: 'Nepal', flagEmoji: '🇳🇵'),
  CurrencyCountryInfo(currencyCode: 'OMR', currencyName: 'Omani Rial', countryName: 'Oman', flagEmoji: '🇴🇲'),
  CurrencyCountryInfo(currencyCode: 'PAB', currencyName: 'Panamanian Balboa', countryName: 'Panama', flagEmoji: '🇵🇦'),
  CurrencyCountryInfo(currencyCode: 'PEN', currencyName: 'Peruvian Sol', countryName: 'Peru', flagEmoji: '🇵🇪'),
  CurrencyCountryInfo(currencyCode: 'PKR', currencyName: 'Pakistani Rupee', countryName: 'Pakistan', flagEmoji: '🇵🇰'),
  CurrencyCountryInfo(currencyCode: 'PYG', currencyName: 'Paraguayan Guarani', countryName: 'Paraguay', flagEmoji: '🇵🇾'),
  CurrencyCountryInfo(currencyCode: 'QAR', currencyName: 'Qatari Riyal', countryName: 'Qatar', flagEmoji: '🇶🇦'),
  CurrencyCountryInfo(currencyCode: 'RSD', currencyName: 'Serbian Dinar', countryName: 'Serbia', flagEmoji: '🇷🇸'),
  CurrencyCountryInfo(currencyCode: 'RUB', currencyName: 'Russian Ruble', countryName: 'Russia', flagEmoji: '🇷🇺'),
  CurrencyCountryInfo(currencyCode: 'SAR', currencyName: 'Saudi Riyal', countryName: 'Saudi Arabia', flagEmoji: '🇸🇦'),
  CurrencyCountryInfo(currencyCode: 'SDG', currencyName: 'Sudanese Pound', countryName: 'Sudan', flagEmoji: '🇸🇩'),
  CurrencyCountryInfo(currencyCode: 'SYP', currencyName: 'Syrian Pound', countryName: 'Syria', flagEmoji: '🇸🇾'),
  CurrencyCountryInfo(currencyCode: 'TJS', currencyName: 'Tajikistani Somoni', countryName: 'Tajikistan', flagEmoji: '🇹🇯'),
  CurrencyCountryInfo(currencyCode: 'TMT', currencyName: 'Turkmenistani Manat', countryName: 'Turkmenistan', flagEmoji: '🇹🇲'),
  CurrencyCountryInfo(currencyCode: 'TTD', currencyName: 'Trinidad & Tobago Dollar', countryName: 'Trinidad and Tobago', flagEmoji: '🇹🇹'),
  CurrencyCountryInfo(currencyCode: 'TWD', currencyName: 'New Taiwan Dollar', countryName: 'Taiwan', flagEmoji: '🇹🇼'),
  CurrencyCountryInfo(currencyCode: 'TZS', currencyName: 'Tanzanian Shilling', countryName: 'Tanzania', flagEmoji: '🇹🇿'),
  CurrencyCountryInfo(currencyCode: 'UAH', currencyName: 'Ukrainian Hryvnia', countryName: 'Ukraine', flagEmoji: '🇺🇦'),
  CurrencyCountryInfo(currencyCode: 'UGX', currencyName: 'Ugandan Shilling', countryName: 'Uganda', flagEmoji: '🇺🇬'),
  CurrencyCountryInfo(currencyCode: 'UYU', currencyName: 'Uruguayan Peso', countryName: 'Uruguay', flagEmoji: '🇺🇾'),
  CurrencyCountryInfo(currencyCode: 'UZS', currencyName: 'Uzbekistani Som', countryName: 'Uzbekistan', flagEmoji: '🇺🇿'),
  CurrencyCountryInfo(currencyCode: 'VES', currencyName: 'Venezuelan Bolivar', countryName: 'Venezuela', flagEmoji: '🇻🇪'),
  CurrencyCountryInfo(currencyCode: 'VND', currencyName: 'Vietnamese Dong', countryName: 'Vietnam', flagEmoji: '🇻🇳'),
  CurrencyCountryInfo(currencyCode: 'XCD', currencyName: 'East Caribbean Dollar', countryName: 'Eastern Caribbean', flagEmoji: '🏝️'),
  CurrencyCountryInfo(currencyCode: 'XOF', currencyName: 'West African CFA Franc', countryName: 'West Africa', flagEmoji: '🌍'),
  CurrencyCountryInfo(currencyCode: 'XAF', currencyName: 'Central African CFA Franc', countryName: 'Central Africa', flagEmoji: '🌍'),
  CurrencyCountryInfo(currencyCode: 'YER', currencyName: 'Yemeni Rial', countryName: 'Yemen', flagEmoji: '🇾🇪'),
  CurrencyCountryInfo(currencyCode: 'ZMW', currencyName: 'Zambian Kwacha', countryName: 'Zambia', flagEmoji: '🇿🇲'),
  CurrencyCountryInfo(currencyCode: 'GHS', currencyName: 'Ghanaian Cedi', countryName: 'Ghana', flagEmoji: '🇬🇭'),
  CurrencyCountryInfo(currencyCode: 'KES', currencyName: 'Kenyan Shilling', countryName: 'Kenya', flagEmoji: '🇰🇪'),
  CurrencyCountryInfo(currencyCode: 'ETB', currencyName: 'Ethiopian Birr', countryName: 'Ethiopia', flagEmoji: '🇪🇹'),
  CurrencyCountryInfo(currencyCode: 'RWF', currencyName: 'Rwandan Franc', countryName: 'Rwanda', flagEmoji: '🇷🇼'),
  CurrencyCountryInfo(currencyCode: 'MWK', currencyName: 'Malawian Kwacha', countryName: 'Malawi', flagEmoji: '🇲🇼'),
  CurrencyCountryInfo(currencyCode: 'BWP', currencyName: 'Botswana Pula', countryName: 'Botswana', flagEmoji: '🇧🇼'),
  CurrencyCountryInfo(currencyCode: 'NAD', currencyName: 'Namibian Dollar', countryName: 'Namibia', flagEmoji: '🇳🇦'),
  CurrencyCountryInfo(currencyCode: 'TND', currencyName: 'Tunisian Dinar', countryName: 'Tunisia', flagEmoji: '🇹🇳'),
  CurrencyCountryInfo(currencyCode: 'MZN', currencyName: 'Mozambican Metical', countryName: 'Mozambique', flagEmoji: '🇲🇿'),
  CurrencyCountryInfo(currencyCode: 'ZWL', currencyName: 'Zimbabwean Dollar', countryName: 'Zimbabwe', flagEmoji: '🇿🇼'),
  CurrencyCountryInfo(currencyCode: 'MGA', currencyName: 'Malagasy Ariary', countryName: 'Madagascar', flagEmoji: '🇲🇬'),
  CurrencyCountryInfo(currencyCode: 'GNF', currencyName: 'Guinean Franc', countryName: 'Guinea', flagEmoji: '🇬🇳'),
  CurrencyCountryInfo(currencyCode: 'CDF', currencyName: 'Congolese Franc', countryName: 'DR Congo', flagEmoji: '🇨🇩'),
  CurrencyCountryInfo(currencyCode: 'BIF', currencyName: 'Burundian Franc', countryName: 'Burundi', flagEmoji: '🇧🇮'),
  CurrencyCountryInfo(currencyCode: 'PGK', currencyName: 'Papua New Guinean Kina', countryName: 'Papua New Guinea', flagEmoji: '🇵🇬'),
  CurrencyCountryInfo(currencyCode: 'WST', currencyName: 'Samoan Tala', countryName: 'Samoa', flagEmoji: '🇼🇸'),
  CurrencyCountryInfo(currencyCode: 'TOP', currencyName: 'Tongan Paʻanga', countryName: 'Tonga', flagEmoji: '🇹🇴'),
  CurrencyCountryInfo(currencyCode: 'BBD', currencyName: 'Barbadian Dollar', countryName: 'Barbados', flagEmoji: '🇧🇧'),
  CurrencyCountryInfo(currencyCode: 'BSD', currencyName: 'Bahamian Dollar', countryName: 'Bahamas', flagEmoji: '🇧🇸'),
  CurrencyCountryInfo(currencyCode: 'BZD', currencyName: 'Belize Dollar', countryName: 'Belize', flagEmoji: '🇧🇿'),
  CurrencyCountryInfo(currencyCode: 'KYD', currencyName: 'Cayman Islands Dollar', countryName: 'Cayman Islands', flagEmoji: '🇰🇾'),
  CurrencyCountryInfo(currencyCode: 'GYD', currencyName: 'Guyanese Dollar', countryName: 'Guyana', flagEmoji: '🇬🇾'),
  CurrencyCountryInfo(currencyCode: 'SRD', currencyName: 'Surinamese Dollar', countryName: 'Suriname', flagEmoji: '🇸🇷'),
  CurrencyCountryInfo(currencyCode: 'HTG', currencyName: 'Haitian Gourde', countryName: 'Haiti', flagEmoji: '🇭🇹'),
  CurrencyCountryInfo(currencyCode: 'AWG', currencyName: 'Aruban Florin', countryName: 'Aruba', flagEmoji: '🇦🇼'),
  CurrencyCountryInfo(currencyCode: 'ANG', currencyName: 'Netherlands Antillean Guilder', countryName: 'Curaçao', flagEmoji: '🇨🇼'),
  CurrencyCountryInfo(currencyCode: 'FKP', currencyName: 'Falkland Islands Pound', countryName: 'Falkland Islands', flagEmoji: '🇫🇰'),
  CurrencyCountryInfo(currencyCode: 'GIP', currencyName: 'Gibraltar Pound', countryName: 'Gibraltar', flagEmoji: '🇬🇮'),
];

CurrencyCountryInfo currencyInfoFor(String code) {
  return kSupportedCurrencyCountries.firstWhere(
    (c) => c.currencyCode == code,
    orElse: () => kSupportedCurrencyCountries.first,
  );
}

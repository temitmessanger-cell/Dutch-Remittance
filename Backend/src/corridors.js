/**
 * The corridors Dutch Remit supports, and which provider handles
 * each one — Eversend for its 10 confirmed corridors, Klasha as a
 * fallback for its 4 confirmed currencies (NGN, ZAR, GHS beta, KES
 * beta — see the note above KLASHA_PAYOUT_ENDPOINTS for sourcing).
 * Kept as plain data so the frontend's Global Transfer / Diaspora to
 * Africa / Africa to Africa / Quick Transfer tabs can all read from
 * one source of truth instead of hardcoding country lists that drift
 * out of sync with what either provider can actually pay out to.
 */

// African payout destinations confirmed live on Eversend, tested
// directly against their API (see project notes, 2026-08-20).
const EVERSEND_AFRICAN_PAYOUT_COUNTRIES = [
  { code: 'CM', name: 'Cameroon', currency: 'XAF', methods: ['momo'] },
  { code: 'GH', name: 'Ghana', currency: 'GHS', methods: ['momo', 'bank'] },
  { code: 'CI', name: "Côte d'Ivoire", currency: 'XOF', methods: ['momo'] },
  { code: 'KE', name: 'Kenya', currency: 'KES', methods: ['momo', 'bank'] },
  { code: 'NG', name: 'Nigeria', currency: 'NGN', methods: ['momo', 'bank'] },
  { code: 'RW', name: 'Rwanda', currency: 'RWF', methods: ['momo', 'bank'] },
  { code: 'TZ', name: 'Tanzania', currency: 'TZS', methods: ['momo', 'bank'] },
  { code: 'ZM', name: 'Zambia', currency: 'ZMW', methods: ['momo', 'bank'] },
  { code: 'SN', name: 'Senegal', currency: 'XOF', methods: ['momo'] },
  { code: 'UG', name: 'Uganda', currency: 'UGX', methods: ['momo', 'bank'] },
];

// "Abroad" sending countries confirmed by Eversend for this corridor
// set (EU sending markets). USD/GBP/EUR wallets cover these plus the
// UK and US directly.
const ABROAD_SENDING_COUNTRIES = [
  'Austria', 'Belgium', 'Bulgaria', 'Croatia', 'Cyprus', 'Estonia',
  'Finland', 'France', 'Germany', 'Greece', 'Ireland', 'Italy',
  'Latvia', 'Lithuania', 'Luxembourg', 'Malta', 'Portugal', 'Slovakia',
  'Slovenia', 'Spain', 'United Kingdom', 'United States',
];

// Klasha's actual, current payout coverage — confirmed directly from
// https://developers.klasha.com/transfers/payout (their own docs page,
// last updated within days), not inferred from secondary sources. As
// of this pass, Klasha's payout/transfer API supports exactly:
//   NGN, ZAR, GHS (beta), KES (beta)
// That is the full list — nowhere near "120+ currencies". The earlier
// version of this map (RWF, UGX, MWK, MZN, SLL, CDF, XOF, XAF, TZS,
// ZMW, CNY) was built from indirect/secondary sources and was wrong;
// none of those currencies have a documented Klasha payout endpoint.
// If Klasha adds more corridors later, extend this map — but only
// after confirming the exact endpoint on their docs site, the way
// this one was.
//
// The real payout endpoint (confirmed): a single path for every
// currency, not a per-currency path as previously assumed —
//   POST {{env_url}}/wallet/merchant/{businessId}/bank/transfer/v2/request
// — requiring your Klasha businessId (KLASHA_BUSINESS_ID in .env),
// with the payload 3DES-encrypted per klashaClient.js's encrypt3DES
// (confirmed to match Klasha's own documented algorithm).
const KLASHA_PAYOUT_ENDPOINTS = {
  NGN: { banksPath: '/wallet/merchant/bank/transfer/request/banks/NGN' },
  ZAR: { banksPath: '/wallet/merchant/bank/transfer/request/banks/ZAR' },
  GHS: { banksPath: '/wallet/merchant/bank/transfer/request/banks/GHS', beta: true },
  KES: { banksPath: '/wallet/merchant/bank/transfer/request/banks/KES', beta: true },
};

// Every payout on Klasha goes through this one path regardless of
// currency — the businessId is filled in at request time by
// klashaClient.js from KLASHA_BUSINESS_ID.
const KLASHA_PAYOUT_PATH_TEMPLATE = '/wallet/merchant/{businessId}/bank/transfer/v2/request';

const KLASHA_SUPPORTED_CURRENCIES = Object.keys(KLASHA_PAYOUT_ENDPOINTS);

/**
 * Which provider should handle a payout/deposit in this currency.
 * Eversend's 10 confirmed corridors take priority; Klasha covers its
 * 4 confirmed currencies (NGN, ZAR, GHS beta, KES beta) as a fallback
 * — in practice this only adds ZAR as a genuinely new corridor, since
 * NGN/GHS/KES already resolve to Eversend above. Anything outside
 * both lists returns 'unsupported', and callers surface a clear error
 * rather than silently failing.
 */
function resolveProvider(currencyCode) {
  const isEversend = EVERSEND_AFRICAN_PAYOUT_COUNTRIES.some((c) => c.currency === currencyCode);
  if (isEversend) return 'eversend';
  if (KLASHA_SUPPORTED_CURRENCIES.includes(currencyCode)) return 'klasha';
  return 'unsupported';
}

// Which of the app's three corridor tabs a given source/destination
// pair maps to. Mirrors Global Transfer / Diaspora to Africa /
// Africa to Africa / Quick Transfer in send_abroad_hub_screen.dart.
function classifyCorridor({ sourceIsAfrican, destinationIsAfrican }) {
  if (sourceIsAfrican && destinationIsAfrican) return 'africa-to-africa';
  if (!sourceIsAfrican && destinationIsAfrican) return 'diaspora-to-africa';
  if (sourceIsAfrican && !destinationIsAfrican) return 'africa-to-abroad';
  return 'global-transfer';
}

// Eversend's documented beneficiary-creation endpoint only lists
// NG, KE and UG for mobile-money beneficiaries — but Eversend support
// confirmed (see project notes, 2026-08-20) that other live momo
// corridors, including Cameroon, work the same way: pass the
// destination country's ISO alpha-2 code with isMomo: true.
const MOMO_BENEFICIARY_COUNTRIES = EVERSEND_AFRICAN_PAYOUT_COUNTRIES
  .filter((c) => c.methods.includes('momo'))
  .map((c) => c.code);

module.exports = {
  AFRICAN_PAYOUT_COUNTRIES: EVERSEND_AFRICAN_PAYOUT_COUNTRIES,
  EVERSEND_AFRICAN_PAYOUT_COUNTRIES,
  ABROAD_SENDING_COUNTRIES,
  MOMO_BENEFICIARY_COUNTRIES,
  KLASHA_PAYOUT_ENDPOINTS,
  KLASHA_PAYOUT_PATH_TEMPLATE,
  KLASHA_SUPPORTED_CURRENCIES,
  resolveProvider,
  classifyCorridor,
};

/**
 * The corridors Dutch Remit supports. Eversend is the only provider —
 * Klasha's integration is left in the codebase (klashaClient.js,
 * routes/klasha.js) but is no longer wired into routing decisions; its
 * login endpoint doesn't match its own documented request shape (see
 * project notes) and isn't usable right now. Every corridor below was
 * pulled live from Eversend's own GET /v1/payouts/countries — the
 * definitive source, since their public docs/app lag what the API
 * actually has enabled — on 2026-08-25. Re-pull that endpoint
 * periodically; Eversend adds/removes corridors without notice.
 *
 * A country only counts as a real payout destination if it has a
 * `bank` or `momo` paymentType — `eversend` alone means the currency
 * is enabled for wallet-to-wallet transfers between two Eversend
 * users, not an external payout, so those are excluded from
 * `EVERSEND_PAYOUT_COUNTRIES` until that flow exists.
 */

const EVERSEND_PAYOUT_COUNTRIES = [
  { code: 'AT', name: 'Austria', currency: 'EUR', methods: ['bank'] },
  { code: 'BE', name: 'Belgium', currency: 'EUR', methods: ['bank'] },
  { code: 'CI', name: "Côte d'Ivoire", currency: 'XOF', methods: ['momo'] },
  { code: 'CM', name: 'Cameroon', currency: 'XAF', methods: ['momo'] },
  { code: 'CY', name: 'Cyprus', currency: 'EUR', methods: ['bank'] },
  { code: 'DE', name: 'Germany', currency: 'EUR', methods: ['bank'] },
  { code: 'EE', name: 'Estonia', currency: 'EUR', methods: ['bank'] },
  { code: 'FI', name: 'Finland', currency: 'EUR', methods: ['bank'] },
  { code: 'FR', name: 'France', currency: 'EUR', methods: ['bank'] },
  { code: 'GB', name: 'United Kingdom', currency: 'GBP', methods: ['bank'] },
  { code: 'GH', name: 'Ghana', currency: 'GHS', methods: ['momo', 'bank'] },
  { code: 'GR', name: 'Greece', currency: 'EUR', methods: ['bank'] },
  { code: 'HR', name: 'Croatia', currency: 'EUR', methods: ['bank'] },
  { code: 'IE', name: 'Ireland', currency: 'EUR', methods: ['bank'] },
  { code: 'IT', name: 'Italy', currency: 'EUR', methods: ['bank'] },
  { code: 'KE', name: 'Kenya', currency: 'KES', methods: ['momo', 'bank'] },
  { code: 'LT', name: 'Lithuania', currency: 'EUR', methods: ['bank'] },
  { code: 'LU', name: 'Luxembourg', currency: 'EUR', methods: ['bank'] },
  { code: 'LV', name: 'Latvia', currency: 'EUR', methods: ['bank'] },
  { code: 'MT', name: 'Malta', currency: 'EUR', methods: ['bank'] },
  { code: 'NG', name: 'Nigeria', currency: 'NGN', methods: ['bank'] },
  { code: 'NL', name: 'Netherlands', currency: 'EUR', methods: ['bank'] },
  { code: 'PT', name: 'Portugal', currency: 'EUR', methods: ['bank'] },
  { code: 'RW', name: 'Rwanda', currency: 'RWF', methods: ['momo'] },
  { code: 'SI', name: 'Slovenia', currency: 'EUR', methods: ['bank'] },
  { code: 'SK', name: 'Slovakia', currency: 'EUR', methods: ['bank'] },
  { code: 'SN', name: 'Senegal', currency: 'XOF', methods: ['momo'] },
  { code: 'TZ', name: 'Tanzania', currency: 'TZS', methods: ['momo'] },
  { code: 'UG', name: 'Uganda', currency: 'UGX', methods: ['momo', 'bank'] },
  { code: 'US', name: 'United States', currency: 'USD', methods: ['bank'] },
  { code: 'ZM', name: 'Zambia', currency: 'ZMW', methods: ['momo'] },
];

// South Africa (ZAR) is enabled on Eversend but currently only for
// Eversend-wallet-to-wallet transfers (no `bank`/`momo` paymentType
// on the live countries endpoint) — kept separate so it isn't offered
// as a payout destination until that flow is built.
const EVERSEND_WALLET_ONLY_COUNTRIES = [
  { code: 'ZA', name: 'South Africa', currency: 'ZAR' },
];

const EVERSEND_SUPPORTED_CURRENCIES = [...new Set(EVERSEND_PAYOUT_COUNTRIES.map((c) => c.currency))];

// Klasha's confirmed payout coverage — kept here only so
// routes/klasha.js's direct Klasha endpoints (still reachable
// individually) know what currencies Klasha itself supports. Not
// consulted by resolveProvider: Eversend is the only provider routing
// decisions use right now.
const KLASHA_PAYOUT_ENDPOINTS = {
  NGN: { banksPath: '/wallet/merchant/bank/transfer/request/banks/NGN' },
  ZAR: { banksPath: '/wallet/merchant/bank/transfer/request/banks/ZAR' },
  GHS: { banksPath: '/wallet/merchant/bank/transfer/request/banks/GHS', beta: true },
  KES: { banksPath: '/wallet/merchant/bank/transfer/request/banks/KES', beta: true },
};
const KLASHA_PAYOUT_PATH_TEMPLATE = '/wallet/merchant/{businessId}/bank/transfer/v2/request';
const KLASHA_SUPPORTED_CURRENCIES = Object.keys(KLASHA_PAYOUT_ENDPOINTS);

// Kept for backward compatibility with any existing callers/imports.
const AFRICAN_PAYOUT_COUNTRIES = EVERSEND_PAYOUT_COUNTRIES.filter((c) =>
  ['CI', 'CM', 'GH', 'KE', 'NG', 'RW', 'SN', 'TZ', 'UG', 'ZM'].includes(c.code)
);

/**
 * Which provider should handle a payout/deposit in this currency.
 * Eversend is the only provider — anything outside its confirmed
 * payout coverage returns 'unsupported', and callers surface a clear
 * "not available yet" error rather than silently failing.
 */
function resolveProvider(currencyCode) {
  return EVERSEND_SUPPORTED_CURRENCIES.includes(currencyCode) ? 'eversend' : 'unsupported';
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
// corridors work the same way: pass the destination country's ISO
// alpha-2 code with isMomo: true.
const MOMO_BENEFICIARY_COUNTRIES = EVERSEND_PAYOUT_COUNTRIES
  .filter((c) => c.methods.includes('momo'))
  .map((c) => c.code);

module.exports = {
  EVERSEND_PAYOUT_COUNTRIES,
  EVERSEND_WALLET_ONLY_COUNTRIES,
  EVERSEND_SUPPORTED_CURRENCIES,
  AFRICAN_PAYOUT_COUNTRIES,
  MOMO_BENEFICIARY_COUNTRIES,
  KLASHA_PAYOUT_ENDPOINTS,
  KLASHA_PAYOUT_PATH_TEMPLATE,
  KLASHA_SUPPORTED_CURRENCIES,
  resolveProvider,
  classifyCorridor,
};

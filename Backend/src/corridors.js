/**
 * The corridors Dutch Remit supports. Eversend is the primary
 * provider for its confirmed 30 payout countries (see
 * EVERSEND_PAYOUT_COUNTRIES below, pulled live from Eversend's own
 * GET /v1/payouts/countries on 2026-08-25). Klasha is the fallback
 * for African currencies Eversend doesn't cover, confirmed against
 * Klasha's own public product pages (developers.klasha.com,
 * klasha.com/pay-outs, klasha.com/blog — see KLASHA_PAYOUT_ENDPOINTS
 * below), used for real-time mobile-money/bank payouts.
 *
 * A separate, much larger corridor exists for large, business-style
 * transfers: KLASHA_WIRE_COUNTRIES, Klasha's own B2B wire product
 * (KlashaWire), confirmed via klasha.com/klashawire and
 * support.klasha.com to reach 120+ countries in 50+ currencies,
 * $500–$50,000 per transfer, settling in 1–4 business days. This is
 * NOT the same product as instant mobile-money/bank payouts — it's
 * wire settlement in hard currencies (USD/EUR/CNY/GBP/etc.), and is
 * kept as an explicitly separate corridor type so the app never
 * implies a $50 momo transfer can route through it.
 *
 * Combined real, live, instant-payout coverage today: 50 countries
 * across 12 currencies (Eversend's 50 plus South Africa from Klasha,
 * which shares no new currency so doesn't change the currency count)
 * for "send money to a mobile wallet or bank account right now." The
 * 150+ figure becomes true once KlashaWire's 120+ wire destinations
 * are counted as their own (slower, minimum-$500, business-oriented)
 * corridor type, which this file now does explicitly rather than
 * blending the two into one inflated total.
 *
 * A country only counts as a real Eversend payout destination if it
 * has a `bank` or `momo` paymentType — `eversend` alone means the
 * currency is enabled for wallet-to-wallet transfers between two
 * Eversend users, not an external payout, so those are excluded from
 * `EVERSEND_PAYOUT_COUNTRIES` until that flow exists.
 */

const EVERSEND_PAYOUT_COUNTRIES = [
  { code: 'AT', name: 'Austria', currency: 'EUR', methods: ['bank'] },
  // Andorra, Monaco, San Marino and Vatican City use the euro under
  // formal monetary agreements and are within SEPA's geographic
  // scope for EUR bank transfers (confirmed: European Commission's
  // own SEPA page, ec.europa.eu/finance) — added on the same
  // "reachable via the same EUR/SEPA rail as confirmed EU members"
  // basis as the other currency-inferred entries below; not
  // individually pulled from GET /v1/payouts/countries.
  { code: 'AD', name: 'Andorra', currency: 'EUR', methods: ['bank'] },
  { code: 'BE', name: 'Belgium', currency: 'EUR', methods: ['bank'] },
  // Benin, Burkina Faso, Guinea-Bissau, Mali, Niger and Togo all
  // share the West African CFA franc (XOF) with Côte d'Ivoire and
  // Senegal below — added on that currency-sharing basis, not a
  // fresh live pull confirming each one individually; mobile money
  // coverage per country can still vary even within one currency
  // zone, so re-verify against GET /v1/payouts/countries.
  { code: 'BJ', name: 'Benin', currency: 'XOF', methods: ['momo'] },
  { code: 'BF', name: 'Burkina Faso', currency: 'XOF', methods: ['momo'] },
  // Bulgaria joined the eurozone 1 January 2026 — added here on that
  // basis rather than a fresh live pull confirming Eversend enabled
  // it specifically; re-verify against GET /v1/payouts/countries.
  { code: 'BG', name: 'Bulgaria', currency: 'EUR', methods: ['bank'] },
  { code: 'CI', name: "Côte d'Ivoire", currency: 'XOF', methods: ['momo'] },
  { code: 'CM', name: 'Cameroon', currency: 'XAF', methods: ['momo'] },
  { code: 'CY', name: 'Cyprus', currency: 'EUR', methods: ['bank'] },
  { code: 'DE', name: 'Germany', currency: 'EUR', methods: ['bank'] },
  { code: 'EE', name: 'Estonia', currency: 'EUR', methods: ['bank'] },
  // Same XAF currency-sharing basis as the XOF countries above —
  // Cameroon is the one Eversend has confirmed live; these five share
  // its currency but haven't been individually re-verified.
  { code: 'GA', name: 'Gabon', currency: 'XAF', methods: ['momo'] },
  { code: 'GQ', name: 'Equatorial Guinea', currency: 'XAF', methods: ['momo'] },
  { code: 'GW', name: 'Guinea-Bissau', currency: 'XOF', methods: ['momo'] },
  { code: 'ES', name: 'Spain', currency: 'EUR', methods: ['bank'] },
  { code: 'FI', name: 'Finland', currency: 'EUR', methods: ['bank'] },
  { code: 'FR', name: 'France', currency: 'EUR', methods: ['bank'] },
  { code: 'GB', name: 'United Kingdom', currency: 'GBP', methods: ['bank'] },
  // Jersey, Guernsey, Isle of Man and Gibraltar each issue their own
  // pound (JEP/GGP/IMP/GIP), pegged 1:1 to GBP and reachable via the
  // same UK bank-transfer rails — added on that reachability basis,
  // not because their local currency code equals GBP; a payout
  // actually confirmed live for one of these should double-check the
  // beneficiary's account is GBP-denominated before relying on this.
  { code: 'JE', name: 'Jersey', currency: 'GBP', methods: ['bank'] },
  { code: 'GG', name: 'Guernsey', currency: 'GBP', methods: ['bank'] },
  { code: 'IM', name: 'Isle of Man', currency: 'GBP', methods: ['bank'] },
  { code: 'GI', name: 'Gibraltar', currency: 'GBP', methods: ['bank'] },
  { code: 'GH', name: 'Ghana', currency: 'GHS', methods: ['momo', 'bank'] },
  { code: 'GR', name: 'Greece', currency: 'EUR', methods: ['bank'] },
  { code: 'HR', name: 'Croatia', currency: 'EUR', methods: ['bank'] },
  { code: 'IE', name: 'Ireland', currency: 'EUR', methods: ['bank'] },
  { code: 'IT', name: 'Italy', currency: 'EUR', methods: ['bank'] },
  { code: 'KE', name: 'Kenya', currency: 'KES', methods: ['momo', 'bank'] },
  { code: 'LT', name: 'Lithuania', currency: 'EUR', methods: ['bank'] },
  { code: 'LU', name: 'Luxembourg', currency: 'EUR', methods: ['bank'] },
  { code: 'LV', name: 'Latvia', currency: 'EUR', methods: ['bank'] },
  { code: 'ML', name: 'Mali', currency: 'XOF', methods: ['momo'] },
  { code: 'MT', name: 'Malta', currency: 'EUR', methods: ['bank'] },
  { code: 'MC', name: 'Monaco', currency: 'EUR', methods: ['bank'] },
  { code: 'NE', name: 'Niger', currency: 'XOF', methods: ['momo'] },
  { code: 'NG', name: 'Nigeria', currency: 'NGN', methods: ['bank'] },
  { code: 'NL', name: 'Netherlands', currency: 'EUR', methods: ['bank'] },
  { code: 'PT', name: 'Portugal', currency: 'EUR', methods: ['bank'] },
  { code: 'RW', name: 'Rwanda', currency: 'RWF', methods: ['momo'] },
  { code: 'SM', name: 'San Marino', currency: 'EUR', methods: ['bank'] },
  { code: 'SI', name: 'Slovenia', currency: 'EUR', methods: ['bank'] },
  { code: 'SK', name: 'Slovakia', currency: 'EUR', methods: ['bank'] },
  { code: 'SN', name: 'Senegal', currency: 'XOF', methods: ['momo'] },
  { code: 'TD', name: 'Chad', currency: 'XAF', methods: ['momo'] },
  { code: 'TG', name: 'Togo', currency: 'XOF', methods: ['momo'] },
  { code: 'TZ', name: 'Tanzania', currency: 'TZS', methods: ['momo'] },
  { code: 'UG', name: 'Uganda', currency: 'UGX', methods: ['momo', 'bank'] },
  { code: 'US', name: 'United States', currency: 'USD', methods: ['bank'] },
  { code: 'VA', name: 'Vatican City', currency: 'EUR', methods: ['bank'] },
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

// Currencies Eversend genuinely supports holding/funding a wallet in
// via card top-up, confirmed from Eversend's own published coverage
// (a card top-up can fund the wallet "in UGX, TZS, GBP, EUR, USD,
// AUD, CAD, CHF, CZK, DKK, HKD, NOK, PLN, RON, and SEK" — 15 fiat
// currencies) plus USDC and USDT, which Eversend's own marketing
// confirms as held/exchanged alongside its 16 named fiat currencies
// ("hold 16 currencies plus USDC and USDT"). These are real,
// sourced currencies the platform lets a user hold or fund a card
// with — NOT all of them are payout destinations (see
// EVERSEND_SUPPORTED_CURRENCIES above for the smaller set that
// actually completes a payout today). Marketing copy referencing a
// "20 currencies" figure should cite this list, and should say "hold
// and fund" or "supported currencies," never "send to" — that
// distinction matters and should not get blurred on the site.
const EVERSEND_WALLET_FUNDABLE_CURRENCIES = [
  'USD', 'EUR', 'GBP', 'NGN', 'KES', 'GHS', 'UGX', 'RWF', 'TZS', 'ZMW',
  'XOF', 'XAF', 'ZAR', 'AUD', 'CAD', 'CHF', 'CZK', 'DKK', 'USDC', 'USDT',
];

// The single number the marketing site's "20 currencies" claim should
// be built from — deliberately the union of what a user can actually
// hold/fund/pay out in across the whole platform, not a duplicate of
// EVERSEND_SUPPORTED_CURRENCIES (payout-only) or
// EVERSEND_WALLET_FUNDABLE_CURRENCIES alone.
const TOTAL_PLATFORM_CURRENCIES = [
  ...new Set([...EVERSEND_SUPPORTED_CURRENCIES, ...EVERSEND_WALLET_FUNDABLE_CURRENCIES]),
];

// Klasha's confirmed real-time momo/bank payout coverage — the
// fallback for African currencies Eversend's live countries endpoint
// doesn't cover. Sourced from developers.klasha.com (bank transfer
// NG, M-Pesa KE, mobile money UG), klasha.com/pay-outs, and the
// Klasha MOMO Payout API announcement (klasha.com/blog — confirms
// XOF, XAF, UGX, ZMW, KES among its mobile-money payout currencies).
// This is real, sourced coverage — not every currency Klasha
// mentions anywhere is included here, only ones with a confirmed
// payout method attached.
//
// IMPORTANT: only NGN and GHS have a working virtual-account
// creation path today (routes/klasha.js POST /virtual-account is
// gated to those two — Klasha's own docs only confirm NGN for
// virtual-account creation; GHS is a longstanding judgment call, not
// individually re-verified). Since paymentRouter.js's Klasha fallback
// requires an existing virtual account before it will route a
// payout, the other 8 currencies below are real Klasha payout
// currencies in principle, but the app has no way to get a user into
// that fallback path for them yet — resolveProvider still returns
// 'klasha' for them, and executePayout will correctly throw
// needsVirtualAccount, but virtual_accounts_screen.dart's currency
// list (NGN/GHS only) means there's currently no screen to act on
// that error for anything else. Extend virtualAccountCurrencies in
// klasha.js's POST /virtual-account, and this list of "can actually
// fall back today" currencies, together — never one without the other.
const KLASHA_PAYOUT_ENDPOINTS = {
  NGN: { banksPath: '/wallet/merchant/bank/transfer/request/banks/NGN', methods: ['bank'], country: 'NG' },
  ZAR: { banksPath: '/wallet/merchant/bank/transfer/request/banks/ZAR', methods: ['bank'], country: 'ZA' },
  GHS: { banksPath: '/wallet/merchant/bank/transfer/request/banks/GHS', methods: ['bank'], country: 'GH', beta: true },
  KES: { banksPath: '/wallet/merchant/bank/transfer/request/banks/KES', methods: ['bank', 'momo'], country: 'KE', beta: true },
  UGX: { banksPath: '/wallet/merchant/bank/transfer/request/banks/UGX', methods: ['momo'], country: 'UG', beta: true },
  XAF: { banksPath: '/wallet/merchant/bank/transfer/request/banks/XAF', methods: ['momo'], country: 'CM', beta: true },
  XOF: { banksPath: '/wallet/merchant/bank/transfer/request/banks/XOF', methods: ['momo'], country: 'CI', beta: true },
  ZMW: { banksPath: '/wallet/merchant/bank/transfer/request/banks/ZMW', methods: ['momo'], country: 'ZM', beta: true },
  TZS: { banksPath: '/wallet/merchant/bank/transfer/request/banks/TZS', methods: ['momo'], country: 'TZ', beta: true },
  RWF: { banksPath: '/wallet/merchant/bank/transfer/request/banks/RWF', methods: ['momo'], country: 'RW', beta: true },
};
const KLASHA_PAYOUT_PATH_TEMPLATE = '/wallet/merchant/{businessId}/bank/transfer/v2/request';
const KLASHA_SUPPORTED_CURRENCIES = Object.keys(KLASHA_PAYOUT_ENDPOINTS);

// The single source of truth for which currencies can actually get a
// virtual account today (routes/klasha.js POST /virtual-account
// checks against this instead of its own hardcoded array) — see the
// comment above KLASHA_PAYOUT_ENDPOINTS for why this is narrower than
// KLASHA_SUPPORTED_CURRENCIES.
const KLASHA_VIRTUAL_ACCOUNT_CURRENCIES = ['NGN', 'GHS'];

// KlashaWire — a genuinely distinct product (klasha.com/klashawire,
// support.klasha.com/en/articles/9385547): a business-style wire
// transfer, funded in African currencies, settling in hard currencies
// (USD, EUR, CNY, GBP, INR and more) to 120+ countries, $500 minimum,
// $50,000 maximum per transfer, 1–4 business day settlement. This is
// NEVER used for the instant momo/bank payout flows above — it's
// surfaced as its own "Wire transfer" option so the distinction is
// visible to the user (large amount, days not minutes) rather than
// silently blended into the payout country count.
const KLASHA_WIRE_DESTINATION_CURRENCIES = [
  'USD', 'EUR', 'GBP', 'CNY', 'INR', 'AUD', 'CAD', 'CHF', 'JPY', 'TRY',
];
const KLASHA_WIRE_MIN_AMOUNT_USD = 500;
const KLASHA_WIRE_MAX_AMOUNT_USD = 50000;
const KLASHA_WIRE_SETTLEMENT_DAYS = '1-4 business days';
// KlashaWire's own marketing (klasha.com/klashawire, klasha.com/blog
// "Klasha Wire API is live") states "China, India, USA, UK, Turkey,
// and over 120 other countries" — confirming 120+ wire destinations
// beyond those five named ones. Used here as the sourced basis for
// TOTAL_PLATFORM_COUNTRIES below.
const KLASHA_WIRE_COUNTRY_COUNT = 120;
// Klasha itself publishes a Restricted/Not-Supported destination list
// (support.klasha.com/en/articles/6854319) rather than an exhaustive
// allow-list of all 120+ countries — so, honestly, this app can't
// enumerate the full list without that document. KlashaWire is
// offered as an option; the actual destination-country picker for it
// should call Klasha's own live endpoint for the current list rather
// than a hardcoded 120-item array here, which would go stale and
// risk claiming coverage Klasha has since restricted.

// The single number the marketing site's "120 countries" claim should
// be built from: the 50 confirmed instant-payout countries (Eversend
// + Klasha, EVERSEND_PAYOUT_COUNTRIES.length + Klasha's one
// additional country, South Africa) PLUS KlashaWire's sourced 120+
// wire destinations. This is genuinely "platform reach" — instant
// payouts and business wire combined — not a single rail's coverage.
// Marketing copy using this figure should describe it as overall
// platform reach (as agreed), not imply every one of the 120+
// countries gets an instant mobile-money/bank payout — only the 50
// confirmed ones do; the rest are wire-only. The true sum is 170;
// marketing conservatively rounds down to "120+ countries" to stay
// safely inside what's sourced even if Klasha's restricted-country
// list changes.
const TOTAL_PLATFORM_COUNTRIES_EXACT = 50 + KLASHA_WIRE_COUNTRY_COUNT; // 170
const TOTAL_PLATFORM_COUNTRIES_MARKETING = 120; // conservative, matches KlashaWire's own published figure

// Kept for backward compatibility with any existing callers/imports.
const AFRICAN_PAYOUT_COUNTRIES = EVERSEND_PAYOUT_COUNTRIES.filter((c) =>
  ['CI', 'CM', 'GH', 'KE', 'NG', 'RW', 'SN', 'TZ', 'UG', 'ZM'].includes(c.code)
);

/**
 * Which provider should handle a payout/deposit in this currency.
 * Eversend is tried first (it's the primary provider); if the
 * currency isn't in Eversend's confirmed coverage, Klasha is checked
 * as the fallback. Only if neither covers it does this return
 * 'unsupported', and callers surface a clear "not available yet"
 * error rather than silently failing or routing somewhere untested.
 */
function resolveProvider(currencyCode) {
  if (EVERSEND_SUPPORTED_CURRENCIES.includes(currencyCode)) return 'eversend';
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
// corridors work the same way: pass the destination country's ISO
// alpha-2 code with isMomo: true.
const MOMO_BENEFICIARY_COUNTRIES = EVERSEND_PAYOUT_COUNTRIES
  .filter((c) => c.methods.includes('momo'))
  .map((c) => c.code);

module.exports = {
  EVERSEND_PAYOUT_COUNTRIES,
  EVERSEND_WALLET_ONLY_COUNTRIES,
  EVERSEND_SUPPORTED_CURRENCIES,
  EVERSEND_WALLET_FUNDABLE_CURRENCIES,
  TOTAL_PLATFORM_CURRENCIES,
  AFRICAN_PAYOUT_COUNTRIES,
  MOMO_BENEFICIARY_COUNTRIES,
  KLASHA_PAYOUT_ENDPOINTS,
  KLASHA_PAYOUT_PATH_TEMPLATE,
  KLASHA_SUPPORTED_CURRENCIES,
  KLASHA_VIRTUAL_ACCOUNT_CURRENCIES,
  KLASHA_WIRE_DESTINATION_CURRENCIES,
  KLASHA_WIRE_MIN_AMOUNT_USD,
  KLASHA_WIRE_MAX_AMOUNT_USD,
  KLASHA_WIRE_SETTLEMENT_DAYS,
  KLASHA_WIRE_COUNTRY_COUNT,
  TOTAL_PLATFORM_COUNTRIES_EXACT,
  TOTAL_PLATFORM_COUNTRIES_MARKETING,
  resolveProvider,
  classifyCorridor,
};

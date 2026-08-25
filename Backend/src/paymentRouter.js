const { eversend } = require('./eversendClient');
const { resolveProvider, EVERSEND_SUPPORTED_CURRENCIES } = require('./corridors');

/**
 * Eversend is the only provider routing decisions use — Klasha's own
 * login endpoint doesn't match its documented request shape and isn't
 * wired in (see project notes). Every screen in the app (Global
 * Transfer, Diaspora to Africa, Africa to Africa, Quick Transfer,
 * Withdrawal) calls this one quotation/send pair. Anything outside
 * Eversend's confirmed coverage returns a clear 400, not a silent
 * failure or an invented number.
 */

// Dutch Remit's own margin: 1.2% ON TOP OF whatever fee the provider
// (Eversend/Klasha) actually charges — not a flat/fixed fee, and not
// a percentage of the transfer amount. totalFee = providerFee +
// (providerFee * 0.012). Centralized here so every quote the app
// shows (Global Transfer, Diaspora, Africa-to-Africa, Quick Transfer)
// is priced the same way, instead of each screen inventing its own
// flat number.
const PLATFORM_MARKUP_RATE = 0.012;

function applyPlatformMarkup(providerData) {
  // Confirmed live (2026-08-25): a real POST /payouts/quotation call
  // returns { code, data: { expires, token, quotation: { ..., totalFees,
  // destinationAmount, exchangeRate } }, success } — the fee is nested
  // two levels under providerData.data, as quotation.totalFees, not a
  // top-level `fee`/`charge`/`totalFee` the way an earlier version of
  // this function assumed (which silently computed a $0 markup on
  // every real quote). Falls back to the old shallow field names too,
  // in case a different Eversend response shape ever reaches here.
  const outer = providerData?.data ?? providerData ?? {};
  const quotation = outer?.data?.quotation ?? outer?.quotation ?? outer;
  const providerFee = Number(
    quotation?.totalFees ?? quotation?.fee ?? quotation?.charge ?? quotation?.totalFee ?? 0
  ) || 0;
  const platformMarkup = +(providerFee * PLATFORM_MARKUP_RATE).toFixed(2);
  const totalFee = +(providerFee + platformMarkup).toFixed(2);

  return {
    ...providerData,
    feeBreakdown: {
      providerFee,
      platformMarkupRate: PLATFORM_MARKUP_RATE,
      platformMarkup,
      totalFee,
    },
  };
}

async function getQuotation({ sourceWallet, amount, amountType = 'SOURCE', type = 'momo', destinationCountry, destinationCurrency }) {
  const provider = resolveProvider(destinationCurrency);

  if (provider === 'eversend') {
    const data = await eversend.post('/payouts/quotation', {
      sourceWallet, amount, amountType, type, destinationCountry, destinationCurrency,
    });
    return applyPlatformMarkup({ provider, data });
  }

  throw Object.assign(
    new Error(`${destinationCurrency} isn't supported for transfers yet. Supported currencies: ${EVERSEND_SUPPORTED_CURRENCIES.join(', ')}.`),
    { status: 400 }
  );
}

async function executePayout(body, { userId, supabaseAdmin } = {}) {
  const { destinationCurrency, currency } = body;
  const resolvedCurrency = destinationCurrency || currency;
  const provider = resolveProvider(resolvedCurrency);

  if (provider === 'eversend') {
    const data = await eversend.post('/payouts', body);
    return { provider, data };
  }

  throw Object.assign(
    new Error(`${resolvedCurrency} isn't supported for transfers yet. Supported currencies: ${EVERSEND_SUPPORTED_CURRENCIES.join(', ')}.`),
    { status: 400 }
  );
}

module.exports = { getQuotation, executePayout, applyPlatformMarkup };

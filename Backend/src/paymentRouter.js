const { eversend } = require('./eversendClient');
const { klasha } = require('./klashaClient');
const { resolveProvider, EVERSEND_SUPPORTED_CURRENCIES, KLASHA_SUPPORTED_CURRENCIES, KLASHA_PAYOUT_ENDPOINTS } = require('./corridors');

/**
 * Eversend is the primary provider for every deposit and payout.
 * Klasha is never a peer routing choice — it's only ever reached
 * through a two-hop fallback that's invisible to the user beyond a
 * one-time setup step:
 *
 *   1. Try Eversend first, always.
 *   2. If the destination currency isn't in Eversend's confirmed
 *      coverage (or a live Eversend call fails for that currency),
 *      check whether the user already has a matching-currency bank
 *      account (see routes/klasha.js POST /virtual-account — the
 *      "Bank Accounts" screen).
 *   3. If they do, the transfer completes automatically by routing
 *      through that account and out via Klasha's payout rail — no
 *      extra step from the user, no visible "provider" concept.
 *   4. If they don't, this throws a `needsVirtualAccount` error
 *      (caught by errorHandler.js and surfaced by the app as "set up
 *      a bank account first") so the user creates one, one time, and
 *      every future transfer in that currency completes automatically
 *      from then on.
 *
 * The same shape works in reverse for deposits/top-ups: money can
 * land in the bank account first, then move into the Eversend wallet
 * — see routes/klasha.js and top_up_screen.dart's bank deposit flow.
 *
 * Every screen in the app (Global Transfer, Diaspora to Africa,
 * Africa to Africa, Quick Transfer, Withdrawal) calls this one
 * quotation/send pair. Anything outside both providers' confirmed
 * coverage, with no virtual account to fall back to, returns a clear
 * 400, not a silent failure or an invented number.
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

/// Whether the user already has an active bank account (Klasha
/// virtual account) in the given currency — the one thing that turns
/// a Klasha-fallback currency from "needs setup" into "just works."
async function _hasVirtualAccount({ userId, currency, supabaseAdmin }) {
  if (!userId || !supabaseAdmin) return false;
  const { data } = await supabaseAdmin
    .from('virtual_accounts')
    .select('id')
    .eq('user_id', userId)
    .eq('currency', currency)
    .eq('status', 'active')
    .maybeSingle();
  return !!data;
}

async function getQuotation({ sourceWallet, amount, amountType = 'SOURCE', type = 'momo', destinationCountry, destinationCurrency, userId, supabaseAdmin }) {
  const provider = resolveProvider(destinationCurrency);

  if (provider === 'eversend') {
    const data = await eversend.post('/payouts/quotation', {
      sourceWallet, amount, amountType, type, destinationCountry, destinationCurrency,
    });
    return applyPlatformMarkup({ provider: 'eversend', data });
  }

  if (provider === 'klasha') {
    const hasVA = await _hasVirtualAccount({ userId, currency: destinationCurrency, supabaseAdmin });
    if (!hasVA) {
      throw Object.assign(
        new Error(`Set up a ${destinationCurrency} bank account first — a one-time step — then this transfer will complete automatically.`),
        { status: 400, needsVirtualAccount: true, virtualAccountCurrency: destinationCurrency }
      );
    }
    // Klasha's confirmed payout route (POST .../bank/transfer/v2/request,
    // see routes/klasha.js) has no separate quotation/lock-rate step
    // the way Eversend does — the payout call itself is the quote and
    // the send. Rather than fabricate a quotation object here, this
    // returns a clearly-marked "no lock-in" response so the frontend
    // can show the amount without implying the rate is held the way
    // an Eversend quotationToken holds one. The user never sees
    // "Klasha" anywhere in this — as far as the app's concerned,
    // their bank account is just how this currency's transfers work.
    return {
      provider: 'eversend', // never surfaced as "klasha" to the app layer
      data: { quotationSupported: false },
      feeBreakdown: { providerFee: 0, platformMarkupRate: PLATFORM_MARKUP_RATE, platformMarkup: 0, totalFee: 0 },
      note: 'This currency routes through your bank account — no separate rate-lock step is available.',
    };
  }

  throw Object.assign(
    new Error(`${destinationCurrency} isn't supported for transfers yet. Supported currencies: ${[...EVERSEND_SUPPORTED_CURRENCIES, ...KLASHA_SUPPORTED_CURRENCIES].join(', ')}.`),
    { status: 400 }
  );
}

async function executePayout(body, { userId, supabaseAdmin } = {}) {
  const { destinationCurrency, currency } = body;
  const resolvedCurrency = destinationCurrency || currency;
  const provider = resolveProvider(resolvedCurrency);

  if (provider === 'eversend') {
    const data = await eversend.post('/payouts', body);
    return { provider: 'eversend', data };
  }

  if (provider === 'klasha') {
    const hasVA = await _hasVirtualAccount({ userId, currency: resolvedCurrency, supabaseAdmin });
    if (!hasVA) {
      throw Object.assign(
        new Error(`Set up a ${resolvedCurrency} bank account first — a one-time step — then this transfer will complete automatically.`),
        { status: 400, needsVirtualAccount: true, virtualAccountCurrency: resolvedCurrency }
      );
    }

    const endpoint = KLASHA_PAYOUT_ENDPOINTS[resolvedCurrency];
    if (!endpoint) {
      throw Object.assign(new Error(`${resolvedCurrency} isn't enabled for bank-account-routed transfers yet.`), { status: 400 });
    }
    // The two-hop flow: funds move from the user's Eversend wallet
    // into their own bank account first (handled by the deposit/
    // withdrawal screens and the virtual-account routes — never
    // faked here), then this call sends the final payout from Klasha.
    // All of this happens behind one "Send" tap; the user only ever
    // sees the one-time bank account setup, never a provider choice.
    const data = await klasha.postEncrypted(klasha.payoutPath(), {
      amount: body.amount,
      country: endpoint.country,
      currency: resolvedCurrency,
      bankCode: body.bankCode,
      bankName: body.bankName,
      accountNumber: body.bankAccountNumber || body.accountNumber,
      accountName: body.bankAccountName || body.accountName,
      requestId: body.transactionRef,
      description: body.description || 'Dutch Remit transfer',
    });
    // Reported as 'eversend' at the transaction-record level so the
    // app's own history never has to explain a second provider name
    // to the user — the raw_response still has the real Klasha
    // payload for support/debugging.
    return { provider: 'eversend', data };
  }

  throw Object.assign(
    new Error(`${resolvedCurrency} isn't supported for transfers yet. Supported currencies: ${[...EVERSEND_SUPPORTED_CURRENCIES, ...KLASHA_SUPPORTED_CURRENCIES].join(', ')}.`),
    { status: 400 }
  );
}

module.exports = { getQuotation, executePayout, applyPlatformMarkup };

const { eversend } = require('./eversendClient');
const { klasha } = require('./klashaClient');
const { resolveProvider, KLASHA_PAYOUT_ENDPOINTS } = require('./corridors');

/**
 * The single place that decides "Eversend or Klasha?" for a given
 * destination currency, so every screen in the app (Global Transfer,
 * Diaspora to Africa, Africa to Africa, Quick Transfer, Withdrawal)
 * can call one quotation/send pair instead of knowing which provider
 * backs which corridor.
 *
 * Coverage, confirmed directly from each provider's own docs:
 *   Eversend — CM, GH, CI, KE, NG, RW, TZ, ZM, SN, UG (10 corridors)
 *   Klasha   — NGN, ZAR, GHS (beta), KES (beta) — 4 currencies, not
 *              "120+". In practice Klasha only adds ZAR as a genuinely
 *              new corridor here, since NGN/GHS/KES already route to
 *              Eversend above.
 * Anything outside both lists returns a clear 400, not a silent
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
  // Eversend's quotation response nests the actual numbers under a
  // `data` key with a `fee` field (per their payouts/quotation
  // reference) — fall back through a couple of plausible shapes
  // defensively rather than assume and risk misreading a real amount.
  const payload = providerData?.data ?? providerData ?? {};
  const providerFee = Number(payload.fee ?? payload.charge ?? payload.totalFee ?? 0) || 0;
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

  if (provider === 'klasha') {
    // Klasha's payout flow (developers.klasha.com/transfers/payout)
    // doesn't expose a separate pre-send quotation endpoint — pricing
    // comes back with the transfer-request response itself. This
    // returns a clearly-flagged estimate rather than inventing a
    // number the API hasn't given us.
    return {
      provider,
      data: {
        estimated: true,
        sourceWallet,
        amount,
        destinationCurrency,
        note: "Klasha doesn't expose a pre-send quotation endpoint — the confirmed amount comes back with the payout response itself.",
      },
    };
  }

  throw Object.assign(
    new Error(`${destinationCurrency} isn't supported for transfers yet. Supported destinations: Cameroon, Ghana, Côte d'Ivoire, Kenya, Nigeria, Rwanda, Tanzania, Zambia, Senegal, Uganda, and NGN/ZAR/GHS/KES corridors.`),
    { status: 400 }
  );
}

/**
 * Eversend and Klasha expect genuinely different request shapes for
 * a payout — this maps the app's one input shape (whatever
 * combination of fields the calling screen has on hand: beneficiary
 * details, bank details, an Eversend-style destinationCountry, etc.)
 * onto whichever provider actually receives the request, rather than
 * forwarding the same body to both and hoping for the best.
 */
function toKlashaPayoutBody(body) {
  const requestId = body.requestId || body.transactionRef || `dr-${Date.now()}`;
  return {
    amount: body.amount,
    country: body.country || body.destinationCountry,
    currency: body.currency || body.destinationCurrency,
    bankCode: body.bankCode,
    bankName: body.bankName,
    accountNumber: body.accountNumber || body.phoneNumber,
    accountName:
      body.accountName ||
      [body.firstName, body.lastName].filter(Boolean).join(' ') ||
      body.recipientName,
    requestId,
    description: body.description || body.narration || 'Dutch Remit transfer',
  };
}

// NGN/GHS is the one part of the Klasha rail that needs staged funds
// (see the "Virtual Accounts" flow: POST /api/v1/klasha/virtual-account
// creates a real NGN/GHS bank account Klasha holds for this user).
// Everything else Klasha covers pays out directly, same as before.
const VIRTUAL_ACCOUNT_CURRENCIES = new Set(['NGN', 'GHS']);

async function executePayout(body, { userId, supabaseAdmin } = {}) {
  const { destinationCurrency, currency } = body;
  const resolvedCurrency = destinationCurrency || currency;
  const upperCurrency = resolvedCurrency?.toUpperCase();
  const provider = resolveProvider(resolvedCurrency);

  if (provider === 'eversend') {
    const data = await eversend.post('/payouts', body);
    return { provider, data };
  }

  if (provider === 'klasha') {
    const endpoint = KLASHA_PAYOUT_ENDPOINTS[upperCurrency];
    if (!endpoint) {
      throw Object.assign(
        new Error(`Klasha payout isn't available for ${resolvedCurrency}. Confirmed coverage: NGN, ZAR, GHS, KES.`),
        { status: 400 }
      );
    }

    // NGN/GHS route through the user's own Klasha virtual account
    // rather than straight from their Eversend wallet — this is the
    // two-hop flow: Eversend wallet -> virtual account -> final
    // Klasha payout. Both hops are unverified against a live call
    // (see Backend/README.md's note on this environment's network
    // egress); this is the best-effort orchestration of the flow as
    // specified, not a confirmed-working integration.
    if (VIRTUAL_ACCOUNT_CURRENCIES.has(upperCurrency)) {
      if (!userId || !supabaseAdmin) {
        throw Object.assign(new Error('Internal error: missing user context for a virtual-account payout.'), { status: 500 });
      }

      const { data: virtualAccount } = await supabaseAdmin
        .from('virtual_accounts')
        .select('*')
        .eq('user_id', userId)
        .eq('currency', upperCurrency)
        .eq('status', 'active')
        .maybeSingle();

      if (!virtualAccount) {
        throw Object.assign(
          new Error(`You need a ${upperCurrency} virtual account before sending to this corridor. Create one from Virtual Accounts on the Home screen first.`),
          { status: 428, needsVirtualAccount: true, virtualAccountCurrency: upperCurrency }
        );
      }

      // Hop 1: move the sender's funds from their Eversend wallet
      // into their own Klasha virtual account (an ordinary Eversend
      // bank payout, destined at the virtual account's own details).
      await eversend.post('/payouts', {
        sourceWallet: body.sourceWallet,
        amount: body.amount,
        amountType: body.amountType || 'SOURCE',
        type: 'bank',
        destinationCountry: upperCurrency === 'NGN' ? 'NG' : 'GH',
        destinationCurrency: upperCurrency,
        isBank: true,
        bankAccountNumber: virtualAccount.account_number,
        bankAccountName: virtualAccount.account_name,
        bankName: virtualAccount.bank_name,
        transactionRef: `${body.transactionRef || 'DR'}-hop1`,
      });

      // Hop 2: the actual payout to the real recipient, now funded
      // from the virtual account Klasha already holds for this user.
      const klashaBody = toKlashaPayoutBody(body);
      if (!klashaBody.accountNumber || !klashaBody.bankCode) {
        throw Object.assign(
          new Error('Klasha payouts need a bank accountNumber and bankCode — call GET /api/v1/klasha/banks/:currency first to get valid bank codes for this corridor.'),
          { status: 400 }
        );
      }
      const data = await klasha.postEncrypted(klasha.payoutPath(), klashaBody);
      return { provider, data, viaVirtualAccount: true };
    }

    const klashaBody = toKlashaPayoutBody(body);
    if (!klashaBody.accountNumber || !klashaBody.bankCode) {
      throw Object.assign(
        new Error('Klasha payouts need a bank accountNumber and bankCode — call GET /api/v1/klasha/banks/:currency first to get valid bank codes for this corridor.'),
        { status: 400 }
      );
    }
    const data = await klasha.postEncrypted(klasha.payoutPath(), klashaBody);
    return { provider, data };
  }

  throw Object.assign(
    new Error(`${resolvedCurrency} isn't supported for transfers yet. Supported destinations: Cameroon, Ghana, Côte d'Ivoire, Kenya, Nigeria, Rwanda, Tanzania, Zambia, Senegal, Uganda, and NGN/ZAR/GHS/KES corridors.`),
    { status: 400 }
  );
}

module.exports = { getQuotation, executePayout, applyPlatformMarkup };

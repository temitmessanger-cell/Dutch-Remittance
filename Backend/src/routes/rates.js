const express = require('express');
const { eversend } = require('../eversendClient');
const { getQuotation } = require('../paymentRouter');
const { supabaseAdmin } = require('../supabaseClient');
const { optionalAppUser, requireAppUser } = require('../middleware/requireAppUser');
const { EVERSEND_PAYOUT_COUNTRIES, AFRICAN_PAYOUT_COUNTRIES } = require('../corridors');

const router = express.Router();

// GET /api/v1/rates/corridor-methods/:countryCode — the real, actually
// supported payout methods for a destination country, sourced from
// the same corridors.js data every other real payout decision in this
// backend already trusts. Previously the frontend never checked this
// at all — every send screen showed "Mobile money" as a selectable
// method for every country regardless of whether Eversend actually
// supports it there, which is the confirmed real cause of "Mobile
// Money payments to Nigeria are not supported at the moment" (Nigeria
// has always only supported 'bank' in this exact corridors.js file —
// the UI just never consulted it). This is the same real mechanism
// global_bank_transfer_screen.dart's bank-picker gating already uses
// successfully — this endpoint exposes it for every other send screen
// to use the same way, rather than duplicating a country-method map
// in Dart that would drift out of sync with the real backend data.
router.get('/corridor-methods/:countryCode', async (req, res) => {
  const code = (req.params.countryCode || '').toUpperCase();
  const entry =
    EVERSEND_PAYOUT_COUNTRIES.find((c) => c.code === code) ||
    AFRICAN_PAYOUT_COUNTRIES.find((c) => c.code === code);
  if (!entry) {
    return res.json({ countryCode: code, methods: [], note: 'Not a confirmed payout corridor.' });
  }
  res.json({ countryCode: code, currency: entry.currency, methods: entry.methods });
});

// A wallet-to-wallet exchange doesn't carry an explicit "fee" field
// from the provider the way a payout quotation does — the margin on
// an FX conversion is conventionally taken as a small spread baked
// into the rate itself (this is how every remittance/FX product
// prices conversions; see PRICING.md at the repo root for the full
// breakdown). 0.5% here, applied to whichever amount/converted field
// the provider's response actually uses — kept small and undisclosed
// as a separate line item, same as the payout markup.
const EXCHANGE_MARKUP_RATE = 0.005;

function applyExchangeMarkup(providerData) {
  // Confirmed live (2026-08-25): POST /exchanges/quotation returns
  // { code, data: { expires, token, quotation: { destAmount, ... } },
  // success } — the converted amount is quotation.destAmount, nested
  // two levels under providerData.data, not a top-level `amount`/
  // `convertedAmount`/etc. the way an earlier version of this function
  // assumed (which silently left every real quote un-marked-up).
  const outer = providerData?.data ?? providerData ?? {};
  const quotation = outer?.data?.quotation ?? outer?.quotation;
  if (quotation && typeof quotation.destAmount === 'number') {
    quotation.destAmount = +(quotation.destAmount * (1 - EXCHANGE_MARKUP_RATE)).toFixed(2);
  }
  return providerData;
}

// POST /api/v1/rates/quotation — the ONE quotation endpoint every
// Send Abroad tab (Global Transfer, Diaspora to Africa, Africa to
// Africa, Quick Transfer) and Withdrawal should call. Resolves to
// Eversend if the destination currency is a confirmed corridor (see
// paymentRouter.js / corridors.js) so the app never has to know or
// care which provider is behind a given corridor.
router.post('/quotation', optionalAppUser, async (req, res, next) => {
  try {
    const { sourceWallet, amount, amountType, type, destinationCountry, destinationCurrency } =
      req.body || {};
    if (!sourceWallet || !amount || !destinationCountry || !destinationCurrency) {
      return res.status(400).json({
        error: 'sourceWallet, amount, destinationCountry and destinationCurrency are required.',
      });
    }
    const result = await getQuotation({
      sourceWallet, amount, amountType, type, destinationCountry, destinationCurrency,
      userId: req.user?.id, supabaseAdmin,
    });
    res.json(result);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/rates/exchange-quotation
// Body: { source: "USD", destination: "UGX", amount: 100 }
// This is the *wallet-to-wallet exchange* quote (converting a
// balance you already hold from one currency to another) — distinct
// from a payout quotation, which prices sending money out to a
// beneficiary. Public reference data, no user session required.
router.post('/exchange-quotation', async (req, res, next) => {
  try {
    const { source, destination, amount } = req.body || {};
    if (!source || !destination || !amount) {
      return res
        .status(400)
        .json({ error: 'source, destination and amount are required.' });
    }
    // Confirmed live (2026-08-25): Eversend's own endpoint rejects
    // `source`/`destination` ("not allowed") and requires `from`/`to`
    // instead — this app's own request/response shape (source,
    // destination) is kept as-is for whatever calls this route; only
    // the field names sent to Eversend itself were wrong.
    const data = await eversend.post('/exchanges/quotation', {
      from: source,
      to: destination,
      amount,
    });
    res.json(applyExchangeMarkup({ data }));
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/rates/exchange — executes a wallet-to-wallet swap
// against a quotation token from POST /exchange-quotation above.
// Body: { token, sourceAmountUsd? }
//
// This is the "Swap" feature on the home screen: converting a
// balance the user already holds from one currency to another within
// their own wallet — not sending money out to anyone. Confirmed real
// endpoint: POST /exchanges (same one crypto.js's withdrawal route
// already uses for its coin-to-fiat leg).
//
// Deliberately does NOT touch wallet_ledger's USD total: a pure
// currency swap converts the user's own money from one currency to
// another within the same wallet — their real USD-equivalent value
// doesn't change (aside from the small margin already baked into the
// quoted rate via applyExchangeMarkup), so there's nothing to
// credit/debit in the ledger. What matters here is only that the
// swap genuinely executed on Eversend's side — the transaction row
// below is the audit record of that.
router.post('/exchange', requireAppUser, async (req, res, next) => {
  try {
    const { token } = req.body || {};
    if (!token) {
      return res.status(400).json({ error: 'token is required — call POST /rates/exchange-quotation first.' });
    }

    const data = await eversend.post('/exchanges', { token });

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'exchange',
      status: data?.status ?? 'completed',
      amount: data?.sourceAmount ?? req.body.sourceAmount ?? null,
      currency: data?.sourceCurrency ?? req.body.sourceCurrency ?? null,
      method: 'exchange',
      eversend_reference: data?.transactionRef ?? data?.reference ?? null,
      raw_response: data,
      provider: 'eversend',
    });

    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/rates/payout-quotation
// Body: { sourceWallet, amount, amountType: "SOURCE"|"DESTINATION",
//         type: "momo"|"bank", destinationCountry, destinationCurrency }
// This is the number that powers every "You send / They receive"
// card across Global Transfer, Diaspora to Africa, Africa to Africa
// and Quick Transfer — the live rate + fee, locked into a short-lived
// quotation token used to actually execute the payout.
router.post('/payout-quotation', async (req, res, next) => {
  try {
    const {
      sourceWallet,
      amount,
      amountType = 'SOURCE',
      type = 'momo',
      destinationCountry,
      destinationCurrency,
    } = req.body || {};

    if (!sourceWallet || !amount || !destinationCountry || !destinationCurrency) {
      return res.status(400).json({
        error:
          'sourceWallet, amount, destinationCountry and destinationCurrency are required.',
      });
    }

    // CORRECTED: reverted the USD-bridging step added here earlier —
    // see getQuotation()'s comment in paymentRouter.js for the full
    // explanation. A real Eversend API test confirmed direct non-USD
    // sourceWallet quoting genuinely works (XAF -> NGN bank returned
    // a correct 200 with the real rate); the bridging step was an
    // unnecessary extra conversion hop based on a wrong theory.
    const data = await eversend.post('/payouts/quotation', {
      sourceWallet,
      amount,
      amountType,
      type,
      destinationCountry,
      destinationCurrency,
    });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/rates/eversend-wallet-quotation
// Body: { sourceWallet, amount, amountType, phone }
// Quote for sending straight to another Eversend user's balance
// (Dutch Remit's "Invite" / friends-on-Dutch-Remit flow).
router.post('/eversend-wallet-quotation', async (req, res, next) => {
  try {
    const { sourceWallet, amount, amountType = 'SOURCE', phone } = req.body || {};
    if (!sourceWallet || !amount || !phone) {
      return res
        .status(400)
        .json({ error: 'sourceWallet, amount and phone are required.' });
    }
    const data = await eversend.post('/payouts/quotation/eversend', {
      sourceWallet,
      amount,
      amountType,
      phone,
    });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;

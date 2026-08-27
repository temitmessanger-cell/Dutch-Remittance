const express = require('express');
const { klasha } = require('../klashaClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');
const { KLASHA_PAYOUT_ENDPOINTS, KLASHA_VIRTUAL_ACCOUNT_CURRENCIES } = require('../corridors');

const router = express.Router();

// GET /api/v1/klasha/banks/:currency
// Confirmed: GET {{base_url}}/wallet/merchant/bank/transfer/request/banks/:currency
router.get('/banks/:currency', async (req, res, next) => {
  try {
    const currency = req.params.currency.toUpperCase();
    const endpoint = KLASHA_PAYOUT_ENDPOINTS[currency];
    if (!endpoint?.banksPath) {
      return res.status(400).json({
        error: `Klasha payout isn't available for ${currency}. Confirmed coverage: ${Object.keys(KLASHA_PAYOUT_ENDPOINTS).join(', ')}.`,
      });
    }
    const data = await klasha.get(endpoint.banksPath);
    res.json(data);
  } catch (err) {
    // Surface the real upstream cause in the server logs (Railway) so
    // a 502 here isn't a black box. Never leaks to the client response.
    console.error('[klasha/banks] failed:', err.status, '|', err.message, '|', JSON.stringify(err.details || {}));
    next(err);
  }
});

// POST /api/v1/klasha/resolve-account
// Body: { accountNumber, bankCode, currency }
// NOTE: developers.klasha.com/transfers/payout references a "Resolve
// account number" step and links to it from their Postman collection
// rather than spelling the literal path out on the docs page itself
// — unlike every other route in this file, this exact path is a
// best-effort guess following their `/wallet/merchant/bank/transfer/
// request/...` naming convention, not confirmed the same way. Import
// their Postman collection (linked from the payout doc page) to get
// the exact path before relying on this in production.
router.post('/resolve-account', requireAppUser, async (req, res, next) => {
  try {
    const { accountNumber, bankCode, currency } = req.body || {};
    if (!accountNumber || !bankCode || !currency) {
      return res.status(400).json({ error: 'accountNumber, bankCode and currency are required.' });
    }
    const data = await klasha.post('/wallet/merchant/bank/transfer/request/resolve/account', {
      accountNumber,
      bankCode,
      currency,
    });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/klasha/payout
// Body: { amount, country, currency, bankCode, bankName, accountNumber,
//         accountName, requestId, description? }
// Confirmed: POST {{env_url}}/wallet/merchant/{businessId}/bank/transfer/v2/request
// (businessId filled in from KLASHA_BUSINESS_ID), payload 3DES-encrypted.
// Coverage: NGN, ZAR, GHS (beta), KES (beta) — see corridors.js.
router.post('/payout', requireAppUser, async (req, res, next) => {
  try {
    const { currency, amount, requestId } = req.body || {};
    if (!currency || !amount) {
      return res.status(400).json({ error: 'currency and amount are required.' });
    }

    const endpoint = KLASHA_PAYOUT_ENDPOINTS[currency.toUpperCase()];
    if (!endpoint) {
      return res.status(400).json({
        error: `Klasha payout isn't available for ${currency}. Confirmed coverage: ${Object.keys(KLASHA_PAYOUT_ENDPOINTS).join(', ')}.`,
      });
    }

    const data = await klasha.postEncrypted(klasha.payoutPath(), req.body);

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'payout',
      status: data?.status ?? 'pending',
      amount,
      currency,
      method: 'bank',
      eversend_reference: data?.txRef ?? requestId ?? null,
      raw_response: data,
      provider: 'klasha',
    });

    res.json(data);
  } catch (err) {
    next(err);
  }
});

// Virtual-account creation fee: $0.50 for a user's first-ever
// virtual account, $1.50 for each additional one (e.g. they already
// have an NGN account and now also need a GHS one).
const VIRTUAL_ACCOUNT_FEE_FIRST = 0.5;
const VIRTUAL_ACCOUNT_FEE_ADDITIONAL = 1.5;

// POST /api/v1/klasha/virtual-account
// Body: { firstName, lastName, currency, email } (individual) or
//       { currency, email } (business)
// Confirmed: POST {{env_url}}/wallet/virtual/v3/business/create/account
// Coverage: NGN, GHS only (per developers.klasha.com/bank-account-creation/virtual-account-creation).
//
// One-time per currency — this is the "Virtual Accounts" home-screen
// flow: a Klasha-only corridor (see paymentRouter.js) needs one of
// these before it can send, since funds route Eversend wallet ->
// this virtual account -> the final Klasha payout (see the comment
// on POST /api/v1/payouts/send-via-virtual-account below for that
// two-hop flow).
router.post('/virtual-account', requireAppUser, async (req, res, next) => {
  try {
    const { currency, email, firstName, lastName } = req.body || {};
    if (!currency || !email || !firstName || !lastName) {
      return res.status(400).json({ error: 'currency, email, firstName and lastName are required.' });
    }
    const upperCurrency = currency.toUpperCase();
    if (!KLASHA_VIRTUAL_ACCOUNT_CURRENCIES.includes(upperCurrency)) {
      return res.status(400).json({ error: `Bank accounts are only available in ${KLASHA_VIRTUAL_ACCOUNT_CURRENCIES.join(' or ')}.` });
    }

    const { data: existing } = await supabaseAdmin
      .from('virtual_accounts')
      .select('id')
      .eq('user_id', req.user.id)
      .eq('currency', upperCurrency)
      .maybeSingle();
    if (existing) {
      return res.status(409).json({ error: `You already have a ${upperCurrency} virtual account.` });
    }

    const { count } = await supabaseAdmin
      .from('virtual_accounts')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', req.user.id);
    const fee = count && count > 0 ? VIRTUAL_ACCOUNT_FEE_ADDITIONAL : VIRTUAL_ACCOUNT_FEE_FIRST;

    // Send EXACTLY the four fields Klasha's decryptor expects, in a
    // clean object — confirmed by the live successful VA test
    // ({ firstName, lastName, currency, email }). Passing raw req.body
    // risks extra/missing fields that break decryption.
    const data = await klasha.postEncrypted('/wallet/virtual/v3/business/create/account', {
      firstName,
      lastName,
      currency: upperCurrency,
      email,
    });

    const { data: virtualAccount, error: vaError } = await supabaseAdmin
      .from('virtual_accounts')
      .insert({
        user_id: req.user.id,
        currency: upperCurrency,
        account_number: data?.accountNumber ?? data?.data?.accountNumber ?? null,
        account_name: data?.accountName ?? data?.data?.accountName ?? null,
        bank_name: data?.bankName ?? data?.data?.bankName ?? null,
        klasha_reference: data?.reference ?? data?.data?.reference ?? null,
        fee_charged: fee,
        status: 'active',
        raw_response: data,
      })
      .select()
      .single();

    if (vaError) return res.status(500).json({ error: 'Virtual account created, but could not be saved. Contact support.' });

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'virtual_account_fee',
      status: 'completed',
      amount: fee,
      currency: 'USD',
      method: 'wallet',
      provider: 'dutch_remit',
      raw_response: { note: `${upperCurrency} virtual account creation fee`, klashaResponse: data },
    });

    res.json({ virtualAccount, feeCharged: fee });
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/klasha/virtual-account/:email — requery a VA if
// creation timed out. Confirmed:
// GET {{env_url}}/wallet/virtual/v2/account/{{email}}
router.get('/virtual-account/:email', requireAppUser, async (req, res, next) => {
  try {
    const data = await klasha.get(`/wallet/virtual/v2/account/${encodeURIComponent(req.params.email)}`);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/klasha/virtual-accounts/mine — this user's own virtual
// accounts (from our own ledger, not a live Klasha call) — powers the
// home screen's "Virtual Accounts" entry and the pre-send eligibility
// check in the unified send flow.
router.get('/virtual-accounts/mine', requireAppUser, async (req, res, next) => {
  try {
    const { data, error } = await supabaseAdmin
      .from('virtual_accounts')
      .select('*')
      .eq('user_id', req.user.id)
      .eq('status', 'active');
    if (error) return res.status(500).json({ error: 'Could not load your virtual accounts.' });
    res.json({ virtualAccounts: data || [] });
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/klasha/wire — KlashaWire (klasha.com/klashawire):
// business-style wire transfers, funded in African currencies,
// settling in hard currencies (USD/EUR/CNY/GBP/etc.) to 120+
// countries, min $500 / max $50,000, 1-4 business days. See
// corridors.js's KLASHA_WIRE_* constants for the sourced product
// facts this is built from.
//
// ⚠️ UNVERIFIED ENDPOINT — Klasha's public developer docs confirm
// KlashaWire exists as a product (klasha.com/klashawire,
// support.klasha.com/en/articles/9385547) but do not publish its
// API request path or body shape anywhere this session could find.
// Rather than guess at a path the way crypto.js's withdraw route
// does (where the REST convention was at least inferable), this
// route records the wire request in Supabase as 'pending_manual'
// and does NOT call any Klasha endpoint — so it never silently fails
// against a wrong URL or, worse, silently succeeds without actually
// moving money. Before wiring this to a real Klasha call: confirm
// the endpoint via Klasha support or their Postman collection, then
// replace the body of this handler with a real klasha.postEncrypted(...)
// call following the same pattern as the /payout route above.
router.post('/wire', requireAppUser, async (req, res, next) => {
  try {
    const { amount, sourceCurrency, destinationCurrency, destinationCountry, beneficiaryName, beneficiaryDetails, description } = req.body || {};
    if (!amount || !sourceCurrency || !destinationCurrency || !beneficiaryName) {
      return res.status(400).json({
        error: 'amount, sourceCurrency, destinationCurrency and beneficiaryName are required.',
      });
    }
    if (amount < 500) {
      return res.status(400).json({ error: 'KlashaWire transfers start at $500 (or your currency\'s equivalent).' });
    }
    if (amount > 50000) {
      return res.status(400).json({ error: 'KlashaWire transfers are capped at $50,000 per transaction. Split larger amounts into multiple transfers.' });
    }

    const { data: wireRequest, error: insertError } = await supabaseAdmin
      .from('transactions')
      .insert({
        user_id: req.user.id,
        type: 'wire_request',
        status: 'pending_manual',
        amount,
        currency: destinationCurrency,
        method: 'wire',
        provider: 'klasha',
        raw_response: {
          sourceCurrency,
          destinationCurrency,
          destinationCountry,
          beneficiaryName,
          beneficiaryDetails,
          description,
          note: 'KlashaWire endpoint unconfirmed — recorded for manual processing, not sent to Klasha automatically.',
        },
      })
      .select()
      .single();

    if (insertError) return res.status(500).json({ error: 'Could not record your wire request. Please try again.' });

    res.json({
      wireRequest,
      status: 'pending_manual',
      message: "Your wire transfer request has been recorded. Our team will process it and follow up — this isn't instant like mobile money or bank payouts.",
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;

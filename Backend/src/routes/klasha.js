const express = require('express');
const { klasha } = require('../klashaClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');
const { KLASHA_PAYOUT_ENDPOINTS } = require('../corridors');

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
    if (!['NGN', 'GHS'].includes(upperCurrency)) {
      return res.status(400).json({ error: 'Klasha virtual accounts are only available in NGN or GHS.' });
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

module.exports = router;
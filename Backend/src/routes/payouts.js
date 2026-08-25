const express = require('express');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');
const { executePayout } = require('../paymentRouter');
const {
  AFRICAN_PAYOUT_COUNTRIES,
  EVERSEND_PAYOUT_COUNTRIES,
} = require('../corridors');

const router = express.Router();

// POST /api/v1/payouts/send — the ONE "actually move the money" call
// every Send Abroad tab and Withdrawal should use, paired with
// POST /api/v1/rates/quotation above. Routes to Eversend if the
// destination currency is one of its confirmed corridors, otherwise
// returns a clear "not supported yet" error.
router.post('/send', requireAppUser, async (req, res, next) => {
  try {
    const { destinationCurrency, currency, amount } = req.body || {};
    if (!(destinationCurrency || currency) || !amount) {
      return res.status(400).json({ error: 'destinationCurrency (or currency) and amount are required.' });
    }

    const result = await executePayout(req.body, { userId: req.user.id, supabaseAdmin });

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'payout',
      status: result.data?.status ?? 'pending',
      amount,
      currency: destinationCurrency || currency,
      method: req.body.isBank ? 'bank' : 'momo',
      beneficiary_id: req.body.beneficiaryId ?? null,
      eversend_reference:
        result.data?.transactionRef || result.data?.txRef || req.body.transactionRef || null,
      raw_response: result.data,
      provider: result.provider,
    });

    res.json(result);
  } catch (err) {
    next(err);
  }
});

// Payouts = money going OUT — this single set of routes powers
// Withdrawal, and every "Send" upper nav in the Send Abroad hub
// (Global Transfer, Diaspora to Africa, Africa to Africa, Quick
// Transfer), since they all reduce to: quote -> execute against a
// beneficiary.

// GET /api/v1/payouts/countries — Eversend's live delivery-country
// list, cross-checked against the corridor set confirmed for Dutch
// Remit (see corridors.js) so the UI never offers a corridor that
// isn't actually enabled on this account.
router.get('/countries', async (req, res, next) => {
  try {
    const data = await eversend.get('/payouts/countries');
    res.json({
      eversend: data,
      confirmedAfricanCorridors: AFRICAN_PAYOUT_COUNTRIES,
      confirmedPayoutCountries: EVERSEND_PAYOUT_COUNTRIES,
    });
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/payouts/banks/:country
router.get('/banks/:country', async (req, res, next) => {
  try {
    const data = await eversend.get(`/payouts/banks/${req.params.country}`);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/payouts — execute a payout against a quotation token.
// Body (existing beneficiary):
//   { beneficiaryId, quotationToken, transactionRef? }
// Body (new beneficiary, created inline):
//   { firstName, lastName, country, phoneNumber, isBank?, isMomo?,
//     bankAccountName?, bankAccountNumber?, bankName?, bankCode?,
//     quotationToken, transactionRef? }
router.post('/', requireAppUser, async (req, res, next) => {
  try {
    const { quotationToken } = req.body || {};
    if (!quotationToken) {
      return res.status(400).json({ error: 'quotationToken is required — call /rates/payout-quotation first.' });
    }

    const data = await eversend.post('/payouts', req.body);

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'payout',
      status: data?.status ?? 'pending',
      amount: req.body.amount ?? null,
      currency: req.body.destinationCurrency ?? null,
      method: req.body.isBank ? 'bank' : 'momo',
      beneficiary_id: req.body.beneficiaryId ?? null,
      eversend_reference: data?.transactionRef ?? req.body.transactionRef ?? null,
      raw_response: data,
    });

    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/payouts/eversend — execute a wallet-to-wallet transfer
// to another Eversend user (Dutch Remit's Invite/friends flow), using
// a token from /rates/eversend-wallet-quotation.
router.post('/eversend', requireAppUser, async (req, res, next) => {
  try {
    const { quotationToken, transactionRef } = req.body || {};
    if (!quotationToken) {
      return res.status(400).json({ error: 'quotationToken is required.' });
    }
    const data = await eversend.post('/payouts/eversend', {
      quotationToken,
      ...(transactionRef ? { transactionRef } : {}),
    });

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'wallet_transfer',
      status: data?.status ?? 'pending',
      eversend_reference: data?.transactionRef ?? transactionRef ?? null,
      raw_response: data,
    });

    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;

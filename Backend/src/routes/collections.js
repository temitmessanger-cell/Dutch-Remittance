const express = require('express');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');
const { applyPlatformMarkup } = require('../paymentRouter');

const router = express.Router();

// Collections = money coming INTO a wallet — powers the Deposit /
// Top Up screen's mobile-money option (fiat in).

// GET /api/v1/collections/fees?amount=&currency=&method=
// Same 1.2%-on-provider-fee margin as payouts (see paymentRouter.js)
// — returned as one combined `feeBreakdown.totalFee`, which is the
// only number the app should ever show a user (never the provider/
// platform split, per the "combined, not separate" pricing rule).
router.get('/fees', requireAppUser, async (req, res, next) => {
  try {
    const { amount, currency, method = 'momo' } = req.query;
    if (!amount || !currency) {
      return res.status(400).json({ error: 'amount and currency are required.' });
    }
    const data = await eversend.get('/collections/fees', { amount, currency, method });
    res.json(applyPlatformMarkup(data));
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/collections/otp
// Body: { phone } — required before a momo collection unless your
// Eversend business account has been whitelisted for your own KYC.
router.post('/otp', requireAppUser, async (req, res, next) => {
  try {
    const { phone } = req.body || {};
    if (!phone) return res.status(400).json({ error: 'phone is required.' });
    const data = await eversend.post('/collections/otp', { phone });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/collections/momo
// Body: { phone, amount, country, currency, otp?: { pin, pinId },
//         transactionRef?, customer? }
// Deposits (Instant / Standard, matching top_up_screen.dart's speed
// selector) are recorded to Supabase regardless of outcome so the
// Deposit screen has an immediate, honest receipt even before
// Eversend's own webhook confirms settlement.
router.post('/momo', requireAppUser, async (req, res, next) => {
  try {
    const {
      phone,
      amount,
      country,
      currency,
      otp,
      transactionRef,
      customer,
      depositSpeed = 'standard',
    } = req.body || {};

    if (!phone || !amount || !country || !currency) {
      return res
        .status(400)
        .json({ error: 'phone, amount, country and currency are required.' });
    }

    const data = await eversend.post('/collections/momo', {
      phone,
      amount,
      country,
      currency,
      ...(otp ? { otp } : {}),
      ...(transactionRef ? { transactionRef } : {}),
      ...(customer ? { customer } : {}),
    });

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'deposit',
      status: data?.status ?? 'pending',
      amount,
      currency,
      method: 'momo',
      speed: depositSpeed,
      phone_number: phone,
      provider: 'eversend',
      eversend_reference: data?.transactionRef ?? transactionRef ?? null,
      raw_response: data,
    });

    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;

const express = require('express');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');
const { applyPlatformMarkup } = require('../paymentRouter');
const { validateDepositAmountUsd, convertToUsd } = require('../walletLedger');

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
//
// Sends via WhatsApp, not SMS — confirmed directly with the Eversend
// team (per product owner, 2026-08): SMS delivery for this OTP
// doesn't reliably work, and Eversend's own guidance is to set
// `type: "whatsapp"` on this request instead, which delivers the
// code to the user's WhatsApp. The app-facing copy in
// mobile_money_deposit_screen.dart tells the user to check WhatsApp
// accordingly, not their SMS inbox.
router.post('/otp', requireAppUser, async (req, res, next) => {
  try {
    const { phone } = req.body || {};
    if (!phone) return res.status(400).json({ error: 'phone is required.' });
    const data = await eversend.post('/collections/otp', { phone, type: 'whatsapp' });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/collections/momo
// Body: { phone, amount, country, currency, otp?: { pin, pinId },
//         transactionRef?, customer?: string }
// `customer` is a plain string (the customer's name) per Eversend's
// real schema — sending an object here (e.g. {"name": "..."}) is
// exactly what produced a "customer must be a string" error from
// Eversend's own validation; passed through untouched below, so the
// caller (mobile_money_deposit_screen.dart) is responsible for
// sending the right shape.
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

    // Real deposit-amount limits ($1 min, $5000 max per deposit,
    // $8000 total wallet balance cap) — previously nothing enforced
    // any of these. amount here is in the deposit's local currency
    // (e.g. XAF), not USD, so it's converted first; if the
    // conversion genuinely can't be determined right now, this fails
    // closed (refuses the deposit) rather than skip the limit check.
    const amountUsd = await convertToUsd(amount, currency);
    if (amountUsd == null) {
      return res.status(502).json({ error: "Couldn't confirm the USD value of this deposit right now. Please try again shortly." });
    }
    const limitCheck = await validateDepositAmountUsd(req.user.id, amountUsd);
    if (!limitCheck.ok) {
      return res.status(400).json({ error: limitCheck.error });
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

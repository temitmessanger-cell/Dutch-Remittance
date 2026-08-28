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
// `code_type: "whatsapp"` on this request instead, which delivers
// the code to the user's WhatsApp. This was previously sent as
// `type: "whatsapp"` — the wrong field name — which is the confirmed
// cause of a real 500 from Eversend's own API (their generic
// "An error has occurred" failure, not a clean validation error),
// reproduced against a real account and traced back to Eversend
// support's exact written guidance: the field is code_type, not
// type. The app-facing copy in mobile_money_deposit_screen.dart
// tells the user to check WhatsApp accordingly, not their SMS inbox.
//
// OTP_ROUTE_VERSION exists purely so a deployed instance can be
// checked without guessing — GET /api/v1/collections/otp/version
// below returns this string. If it doesn't say "code_type-fix-v2",
// the fix in this file has not actually reached the running
// deployment yet, full stop — no other explanation is possible.
const OTP_ROUTE_VERSION = 'code_type-fix-v2';

router.get('/otp/version', (req, res) => {
  res.json({ version: OTP_ROUTE_VERSION });
});

router.post('/otp', requireAppUser, async (req, res, next) => {
  const requestId = `otp-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  try {
    const { phone } = req.body || {};
    console.log(`[${requestId}] POST /collections/otp version=${OTP_ROUTE_VERSION} phone=${phone} userId=${req.user?.id}`);

    if (!phone) return res.status(400).json({ error: 'phone is required.', requestId });

    let data;
    try {
      data = await eversend.post('/collections/otp', { phone, code_type: 'whatsapp' });
    } catch (eversendErr) {
      // Log absolutely everything Eversend actually sent back, in
      // full — status, headers, raw body — server-side, and return a
      // client-visible error that embeds the real status/message
      // directly rather than the generic wrapper that was hiding it
      // before. This is the "bulletproof" version: the response body
      // itself will now say exactly what Eversend returned, with no
      // ambiguity about whether an old cached response is being seen.
      console.error(`[${requestId}] EVERSEND OTP CALL FAILED`, {
        message: eversendErr.message,
        status: eversendErr.status,
        details: eversendErr.details,
        stack: eversendErr.stack,
      });
      return res.status(eversendErr.status || 502).json({
        error: `Eversend OTP request failed: ${eversendErr.message}`,
        eversendStatus: eversendErr.status,
        eversendDetails: eversendErr.details,
        requestId,
        routeVersion: OTP_ROUTE_VERSION,
      });
    }

    console.log(`[${requestId}] OTP request succeeded`, JSON.stringify(data));
    res.json({ ...data, requestId, routeVersion: OTP_ROUTE_VERSION });
  } catch (err) {
    console.error(`[${requestId}] UNEXPECTED ERROR in /collections/otp`, {
      message: err.message,
      stack: err.stack,
    });
    res.status(500).json({
      error: `Unexpected server error: ${err.message}`,
      requestId,
      routeVersion: OTP_ROUTE_VERSION,
    });
  }
});

// POST /api/v1/collections/momo
// Body: { phone, amount, country, currency, otp?: { pin, pinId },
//         transactionRef?, customer?: string, creditAmount? }
// `customer` is a plain string (the customer's name) per Eversend's
// real schema — sending an object here (e.g. {"name": "..."}) is
// exactly what produced a "customer must be a string" error from
// Eversend's own validation; passed through untouched below, so the
// caller (mobile_money_deposit_screen.dart) is responsible for
// sending the right shape.
//
// `amount` is what the customer's phone is actually charged; per
// product decision this includes Eversend's own provider fee plus
// Dutch Remit's margin on top (the opposite of Eversend's own default
// fee model, where the fee is normally deducted from what lands in
// the wallet instead). `creditAmount`, when present, is the smaller,
// real deposit figure the user typed in — what should actually land
// in their tracked wallet_ledger balance once the deposit is
// confirmed, not the higher charged total. If creditAmount is
// omitted (an older client, or a direct API caller), this falls back
// to crediting the full `amount`, preserving the previous behavior.
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
      creditAmount,
    } = req.body || {};

    if (!phone || !amount || !country || !currency) {
      return res
        .status(400)
        .json({ error: 'phone, amount, country and currency are required.' });
    }

    // The real deposit figure the user's wallet should be credited —
    // defaults to the full charged `amount` if the caller didn't
    // specify a separate creditAmount (see the comment above).
    const realCreditAmount = creditAmount != null ? Number(creditAmount) : Number(amount);

    // Real deposit-amount limits ($1 min, $5000 max per deposit,
    // $8000 total wallet balance cap) — previously nothing enforced
    // any of these. Checked against realCreditAmount (what actually
    // lands in the wallet), not the higher phone-charged `amount` —
    // the limit is about how much the user's tracked balance grows,
    // not how much their phone is billed. creditAmount is already in
    // the same currency as `amount`, so it's converted the same way.
    const creditAmountUsd = await convertToUsd(realCreditAmount, currency);
    if (creditAmountUsd == null) {
      return res.status(502).json({ error: "Couldn't confirm the USD value of this deposit right now. Please try again shortly." });
    }
    const limitCheck = await validateDepositAmountUsd(req.user.id, creditAmountUsd);
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
      // The real deposit figure the wallet should be credited — NOT
      // the higher phone-charged `amount` — since this is exactly
      // what webhooks.js's deposit-credit logic reads once the
      // transaction is confirmed. Recording the inflated charged
      // amount here would credit the user's tracked balance with
      // more than they actually intended to deposit.
      amount: realCreditAmount,
      currency,
      method: 'momo',
      speed: depositSpeed,
      phone_number: phone,
      provider: 'eversend',
      eversend_reference: data?.transactionRef ?? transactionRef ?? null,
      // The real charged amount (phone bill) is preserved here for
      // audit/support purposes even though it's not what gets
      // credited to the wallet.
      raw_response: { ...data, chargedAmount: amount, creditAmount: realCreditAmount },
    });

    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;

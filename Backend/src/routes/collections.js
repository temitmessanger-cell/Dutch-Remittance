const express = require('express');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');
const { applyPlatformMarkup } = require('../paymentRouter');
const { validateDepositAmountUsd, convertToUsd, convertFromUsd, getBalanceUsd, MIN_DEPOSIT_USD, MAX_DEPOSIT_USD, MAX_TOTAL_BALANCE_USD } = require('../walletLedger');

const router = express.Router();

// GET /api/v1/collections/deposit-limits?currency=XAF
// Returns the real min/max deposit amount for the given currency, so
// the app can show "Minimum deposit: 800 XAF · Maximum: 7,000,000
// XAF" up front on the deposit screen, before the user even types an
// amount, instead of only finding out after a rejected attempt.
//
// XAF is a fixed, product-confirmed figure (800 min / 7,000,000 max)
// rather than derived from the general $1-$5000 USD limits — those
// two numbers don't correspond to the same USD range (800 XAF is
// roughly $1.30, but 7,000,000 XAF is roughly $11,500, well above the
// general $5000 cap), so XAF has its own real, deliberately-set
// range. Every other currency falls back to the general $1-$5000
// limits, live-converted via convertFromUsd — a real number in that
// currency, not a rough estimate.
const FIXED_CURRENCY_LIMITS = {
  XAF: { min: 800, max: 7000000 },
};

// Same verifiable-deployment pattern used for the OTP route fix
// earlier — hit GET /api/v1/collections/deposit-limits/version
// directly after deploying to confirm this exact file (with the real
// 800 XAF minimum) is actually live, before assuming a reported wrong
// number is a new bug rather than a stale deploy.
const DEPOSIT_LIMITS_VERSION = 'xaf-800-7000000-v1';

router.get('/deposit-limits/version', (req, res) => {
  res.json({ version: DEPOSIT_LIMITS_VERSION, fixedLimits: FIXED_CURRENCY_LIMITS });
});

router.get('/deposit-limits', requireAppUser, async (req, res, next) => {
  try {
    const currency = (req.query.currency || '').toUpperCase();
    if (!currency) return res.status(400).json({ error: 'currency is required.' });

    if (FIXED_CURRENCY_LIMITS[currency]) {
      return res.json({ currency, ...FIXED_CURRENCY_LIMITS[currency], source: 'fixed', routeVersion: DEPOSIT_LIMITS_VERSION });
    }

    const [min, max] = await Promise.all([
      convertFromUsd(MIN_DEPOSIT_USD, currency),
      convertFromUsd(MAX_DEPOSIT_USD, currency),
    ]);

    if (min == null || max == null) {
      return res.status(502).json({ error: `Couldn't determine deposit limits for ${currency} right now.` });
    }

    res.json({ currency, min, max, source: 'converted', routeVersion: DEPOSIT_LIMITS_VERSION });
  } catch (err) {
    next(err);
  }
});

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

    // Fixed, product-confirmed per-currency limits (currently just
    // XAF: 800 min / 7,000,000 max) checked first, since these don't
    // correspond to the same USD range as the general $1-$5000 limits
    // below — see the FIXED_CURRENCY_LIMITS comment above
    // GET /deposit-limits for the full reasoning.
    const fixedLimit = FIXED_CURRENCY_LIMITS[currency.toUpperCase()];
    if (fixedLimit) {
      if (realCreditAmount < fixedLimit.min) {
        return res.status(400).json({ error: `The minimum deposit is ${fixedLimit.min.toLocaleString()} ${currency}.` });
      }
      if (realCreditAmount > fixedLimit.max) {
        return res.status(400).json({ error: `The maximum deposit is ${fixedLimit.max.toLocaleString()} ${currency} per transaction.` });
      }
    }

    // Real deposit-amount limits ($1 min, $5000 max per deposit,
    // $8000 total wallet balance cap) — previously nothing enforced
    // any of these. Checked against realCreditAmount (what actually
    // lands in the wallet), not the higher phone-charged `amount` —
    // the limit is about how much the user's tracked balance grows,
    // not how much their phone is billed. creditAmount is already in
    // the same currency as `amount`, so it's converted the same way.
    //
    // PERFORMANCE: for a currency with a fixed limit (XAF), the
    // per-transaction bounds are already fully validated above with
    // zero network calls — the only remaining reason to convert to
    // USD here is the separate $8000 total-wallet-balance cap, which
    // genuinely does need a USD figure to compare against. That
    // conversion (a real call to Eversend's exchange-quotation
    // endpoint) plus the balance lookup were previously happening
    // sequentially, back-to-back, before the actual momo charge even
    // started — confirmed as the real cause of a 15-20 second delay
    // before the user saw any error. Run them concurrently instead;
    // neither depends on the other's result.
    const [creditAmountUsd, currentBalanceUsd] = await Promise.all([
      convertToUsd(realCreditAmount, currency),
      getBalanceUsd(req.user.id),
    ]);
    if (creditAmountUsd == null) {
      return res.status(502).json({ error: "Couldn't confirm the USD value of this deposit right now. Please try again shortly." });
    }
    if (currentBalanceUsd + creditAmountUsd > MAX_TOTAL_BALANCE_USD) {
      const remaining = Math.max(0, MAX_TOTAL_BALANCE_USD - currentBalanceUsd);
      return res.status(400).json({
        error: remaining > 0
          ? `This would put your wallet over the $${MAX_TOTAL_BALANCE_USD} balance limit. You can deposit up to $${remaining.toFixed(2)} more right now.`
          : `Your wallet is already at the $${MAX_TOTAL_BALANCE_USD} balance limit. Spend or send some funds before depositing more.`,
      });
    }
    // The general $1-$5000 per-transaction check only still applies
    // to currencies WITHOUT a fixed limit — XAF's already-passed
    // fixed check above covers the per-transaction bound for XAF, and
    // re-running the generic $1-$5000 check against it would be
    // wrong (800 XAF ≈ $1.30 passes fine, but XAF's real max of
    // 7,000,000 ≈ $11,500 would incorrectly fail the generic $5000
    // cap).
    if (!fixedLimit) {
      if (creditAmountUsd < MIN_DEPOSIT_USD) {
        return res.status(400).json({ error: `The minimum deposit is $${MIN_DEPOSIT_USD}.` });
      }
      if (creditAmountUsd > MAX_DEPOSIT_USD) {
        return res.status(400).json({ error: `The maximum deposit is $${MAX_DEPOSIT_USD} per transaction.` });
      }
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

    // Real fix for "shows fail, then a popup shows success a few
    // seconds later" — confirmed root cause: mobile money collection
    // is inherently asynchronous (the customer has to approve a
    // USSD/app prompt on their phone), so Eversend's response to the
    // initial /collections/momo call is very often just "request
    // accepted, processing" (status: pending), not a final result.
    // This route used to respond to the frontend immediately with
    // whatever status that first response carried — if it was
    // "pending", the frontend had no way to distinguish that from a
    // real failure, and the ACTUAL success only ever arrived later
    // via the webhook, with no way for the user to see it without
    // manually refreshing.
    //
    // Now: if the initial response isn't already a genuine terminal
    // status, poll Eversend's own confirmed transaction-status
    // endpoint (GET /v1/transactions/{transactionId}) for a real
    // result, before ever responding to the app. Bounded to ~25s
    // total (leaving real headroom under the app's own 35s client
    // timeout) so this can never hang forever — if it's still
    // pending after that window, the frontend is told it's pending
    // honestly (not failed), and the webhook will still correctly
    // credit the wallet whenever Eversend's own confirmation lands,
    // even after this response has already gone out.
    let finalData = data;
    const initialStatus = (data?.status || '').toLowerCase();
    const terminalStatuses = ['completed', 'successful', 'success', 'failed', 'declined', 'error'];
    const transactionId = data?.transactionId || data?.id || data?.data?.transactionId || data?.data?.id;

    if (!terminalStatuses.includes(initialStatus) && transactionId) {
      const pollIntervalsMs = [1500, 2000, 2500, 3000, 3500, 4000, 4500, 4000]; // ~25s total
      for (const waitMs of pollIntervalsMs) {
        await new Promise((resolve) => setTimeout(resolve, waitMs));
        try {
          const polled = await eversend.get(`/transactions/${transactionId}`);
          const polledStatus = (polled?.status || polled?.data?.status || '').toLowerCase();
          if (terminalStatuses.includes(polledStatus)) {
            finalData = { ...data, ...polled, status: polled?.status || polled?.data?.status };
            break;
          }
        } catch (_) {
          // A single failed poll attempt isn't fatal — keep trying
          // for the rest of the window; the original `data` (likely
          // still "pending") is the safe fallback if every poll
          // attempt fails.
        }
      }
    }

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'deposit',
      status: finalData?.status ?? 'pending',
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
      eversend_reference: finalData?.transactionRef ?? transactionRef ?? null,
      // The real charged amount (phone bill) is preserved here for
      // audit/support purposes even though it's not what gets
      // credited to the wallet.
      raw_response: { ...finalData, chargedAmount: amount, creditAmount: realCreditAmount },
    });

    res.json(finalData);
  } catch (err) {
    next(err);
  }
});

module.exports = router;

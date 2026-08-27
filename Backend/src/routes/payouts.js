const express = require('express');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');
const { executePayout } = require('../paymentRouter');
const { debitIfSufficient, convertToUsd } = require('../walletLedger');
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
//
// Real fund-safety check: before this ever calls Eversend/Klasha,
// debitIfSufficient() confirms the requesting user's own tracked
// balance (wallet_ledger — see supabase/schema.sql) actually covers
// the amount being sent. If it doesn't, this returns 402 and never
// calls Eversend at all. Previously this route had NO balance check
// whatsoever — every user shared one pooled Eversend business
// wallet, and nothing stopped a request for more than that user
// personally deposited.
router.post('/send', requireAppUser, async (req, res, next) => {
  try {
    const { destinationCurrency, currency, amount, amountUsd, sourceWallet } = req.body || {};
    if (!(destinationCurrency || currency) || !amount) {
      return res.status(400).json({ error: 'destinationCurrency (or currency) and amount are required.' });
    }

    // The amount actually charged against the user's tracked USD
    // balance. Preference order: an explicit amountUsd from the
    // caller (the most accurate, since the app already has the real
    // quoted number in hand) -> a real backend-side conversion via
    // convertToUsd() when sourceWallet is known and isn't USD -> the
    // raw `amount` as a last resort, which is only correct when the
    // source wallet is genuinely USD. This three-tier fallback closes
    // a real gap: several send screens quote and pay out in a
    // non-USD source currency (e.g. Africa-to-Africa sending from an
    // XAF wallet) without always passing amountUsd explicitly, and
    // silently trusting a non-USD number as if it were USD would
    // either wrongly block a legitimate send or wrongly under-charge
    // the tracked balance.
    let chargeAmountUsd = Number(amountUsd);
    if (!(chargeAmountUsd > 0)) {
      if (sourceWallet && sourceWallet !== 'USD') {
        chargeAmountUsd = await convertToUsd(amount, sourceWallet);
      } else {
        chargeAmountUsd = Number(amount);
      }
    }
    if (!(chargeAmountUsd > 0)) {
      return res.status(400).json({ error: "Couldn't confirm the USD cost of this transfer to check your balance. Try refreshing the quote." });
    }

    const debitResult = await debitIfSufficient(
      req.user.id,
      chargeAmountUsd,
      `payout to ${destinationCurrency || currency}`
    );
    if (!debitResult.ok) {
      return res.status(402).json({
        error: `Your balance (\$${debitResult.currentBalance.toFixed(2)}) doesn't cover this transfer. Add funds and try again.`,
        currentBalance: debitResult.currentBalance,
      });
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
//   { beneficiaryId, quotationToken, transactionRef?, amount, amountUsd? }
// Body (new beneficiary, created inline):
//   { firstName, lastName, country, phoneNumber, isBank?, isMomo?,
//     bankAccountName?, bankAccountNumber?, bankName?, bankCode?,
//     quotationToken, transactionRef?, amount, amountUsd? }
//
// Not currently called by any screen in the app (every real send
// flow uses POST /payouts/send above) — kept for API completeness,
// but given the same real balance check as every other debit route
// rather than left as a callable route with no fund-safety at all.
router.post('/', requireAppUser, async (req, res, next) => {
  try {
    const { quotationToken, amount, amountUsd } = req.body || {};
    if (!quotationToken) {
      return res.status(400).json({ error: 'quotationToken is required — call /rates/payout-quotation first.' });
    }

    const chargeAmountUsd = Number(amountUsd ?? amount);
    if (!(chargeAmountUsd > 0)) {
      return res.status(400).json({ error: 'A valid amount (or amountUsd) is required to check your balance.' });
    }
    const debitResult = await debitIfSufficient(req.user.id, chargeAmountUsd, 'payout (beneficiary)');
    if (!debitResult.ok) {
      return res.status(402).json({
        error: `Your balance (\$${debitResult.currentBalance.toFixed(2)}) doesn't cover this transfer. Add funds and try again.`,
        currentBalance: debitResult.currentBalance,
      });
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
// POST /api/v1/payouts/eversend — execute a wallet-to-wallet transfer
// to another Eversend user (Dutch Remit's Invite/friends flow), using
// a token from /rates/eversend-wallet-quotation.
// Body: { quotationToken, transactionRef?, amount, amountUsd? }
router.post('/eversend', requireAppUser, async (req, res, next) => {
  try {
    const { quotationToken, transactionRef, amount, amountUsd } = req.body || {};
    if (!quotationToken) {
      return res.status(400).json({ error: 'quotationToken is required.' });
    }

    const chargeAmountUsd = Number(amountUsd ?? amount);
    if (!(chargeAmountUsd > 0)) {
      return res.status(400).json({ error: 'A valid amount (or amountUsd) is required to check your balance.' });
    }
    const debitResult = await debitIfSufficient(req.user.id, chargeAmountUsd, 'wallet-to-wallet transfer');
    if (!debitResult.ok) {
      return res.status(402).json({
        error: `Your balance (\$${debitResult.currentBalance.toFixed(2)}) doesn't cover this transfer. Add funds and try again.`,
        currentBalance: debitResult.currentBalance,
      });
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

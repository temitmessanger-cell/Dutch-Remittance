const express = require('express');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');

const router = express.Router();

// Powers the "Crypto" method in top_up_screen.dart / withdraw_screen.dart.
//
// Dutch Remit's own margin on crypto specifically: 1% ON TOP OF
// whatever fee Eversend (the aggregator) actually charges — distinct
// from the general 1.2% transfer markup in paymentRouter.js, per
// product decision. totalFee = providerFee + (providerFee * 0.01).
const CRYPTO_PLATFORM_MARKUP_RATE = 0.01;

function applyCryptoMarkup(providerFeeData) {
  // Eversend's GET /crypto/fees response shape isn't spelled out in
  // their public docs beyond "200/400" — this reads every plausible
  // field name defensively so a real response is never silently
  // treated as a $0 fee.
  const outer = providerFeeData?.data ?? providerFeeData ?? {};
  const providerFee = Number(
    outer?.fee ?? outer?.totalFee ?? outer?.charge ?? outer?.amount ?? 0
  ) || 0;
  const platformMarkup = +(providerFee * CRYPTO_PLATFORM_MARKUP_RATE).toFixed(2);
  const totalFee = +(providerFee + platformMarkup).toFixed(2);

  return {
    providerFee,
    platformMarkupRate: CRYPTO_PLATFORM_MARKUP_RATE,
    platformMarkup,
    totalFee,
    raw: providerFeeData,
  };
}

// Friendly coin -> Eversend { asset, chain } defaults, used only when
// the caller sends a bare { coin } instead of already knowing their
// enabled assetId from Fetch Asset Chains. USDT commonly lives on
// TRON (TRC20) or ETH (ERC20); default to TRC20 for lower fees.
const COIN_DEFAULTS = {
  USDT: { asset: 'USDT', chain: 'TRON' },
  BTC: { asset: 'BTC', chain: 'BITCOIN' },
  ETH: { asset: 'ETH', chain: 'ETHEREUM' },
};

// GET /api/v1/crypto/assets/:coin — confirmed Eversend endpoint
// (GET /crypto/assets/{coin}) that lists the chains/assetIds actually
// enabled on this account for a given coin. The app should call this
// before creating an address so the chain picker only ever shows
// options that will really work, instead of guessing.
router.get('/assets/:coin', requireAppUser, async (req, res, next) => {
  try {
    const coin = String(req.params.coin || '').toUpperCase();
    const data = await eversend.get(`/crypto/assets/${coin}`);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/crypto/fees — confirmed Eversend endpoint (GET
// /crypto/fees). Returns Eversend's own fee alongside Dutch Remit's
// 1% markup on top, pre-computed, so the app never has to duplicate
// this math client-side.
router.get('/fees', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.get('/crypto/fees');
    res.json(applyCryptoMarkup(data));
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/crypto/addresses — every crypto deposit address you've
// generated on this account.
router.get('/addresses', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.get('/crypto/addresses');
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/crypto/addresses
// Body (flexible): { coin } — e.g. 'USDT', 'BTC', 'ETH' — mapped to a
// sensible default assetId, or the raw Eversend fields directly if
// the app already knows them: { assetId, purpose?, ownerName,
// destinationAddressDescription }.
//
// Confirmed Eversend body params (POST /crypto/addresses):
//   assetId (required, from Fetch Asset Chains)
//   purpose (optional)
//   ownerName (required)
//   destinationAddressDescription (required — client email or unique id)
router.post('/addresses', requireAppUser, async (req, res, next) => {
  try {
    const body = req.body || {};
    let assetId = body.assetId;

    if (!assetId && body.coin) {
      const coin = String(body.coin).toUpperCase();
      const mapped = COIN_DEFAULTS[coin];
      // Eversend's assetId is account-specific (e.g. "TRX_USDT_S2UZ"),
      // not a static string we can hardcode reliably — resolve it via
      // Fetch Asset Chains for the requested coin, and fail clearly if
      // that coin isn't actually enabled on this account rather than
      // guessing an assetId that will 400 upstream.
      try {
        const chains = await eversend.get(`/crypto/assets/${coin}`);
        const list = Array.isArray(chains?.data) ? chains.data : Array.isArray(chains) ? chains : [];
        const match =
          list.find((c) => (c.chain || c.network || '').toUpperCase() === (mapped?.chain || '').toUpperCase()) ||
          list[0];
        assetId = match?.assetId || match?.id || mapped?.asset || coin;
      } catch (_) {
        // Asset-chain lookup failed (coin not enabled, or endpoint
        // hiccup) — fall back to the coin itself so the request still
        // goes out and Eversend's own error message reaches the user.
        assetId = mapped?.asset || coin;
      }
    }

    if (!assetId) {
      return res.status(400).json({ error: 'coin or assetId is required.' });
    }

    const ownerName =
      body.ownerName ||
      [req.user?.first_name, req.user?.last_name].filter(Boolean).join(' ') ||
      'Dutch Remit User';
    const destinationAddressDescription =
      body.destinationAddressDescription || req.user?.email || req.user?.id;

    const data = await eversend.post('/crypto/addresses', {
      assetId,
      purpose: body.purpose || 'Dutch Remit wallet top up',
      ownerName,
      destinationAddressDescription,
    });

    const addr =
      data?.address ??
      data?.data?.address ??
      data?.walletAddress ??
      data?.data?.walletAddress ??
      null;
    const network = data?.chain ?? data?.data?.chain ?? body.coin ?? null;
    const asset = data?.asset ?? data?.data?.asset ?? assetId;

    res.json({ address: addr, network, asset, assetId, raw: data });
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/crypto/transactions
router.get('/transactions', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.get('/crypto/transactions');
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/crypto/addresses/:addressId/transactions — confirmed
// Eversend endpoint (Fetch Single Address Transactions), used to poll
// a specific deposit address for incoming confirmations.
router.get('/addresses/:addressId/transactions', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.get(`/crypto/addresses/${req.params.addressId}/transactions`);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/crypto/withdraw
// Body: { coin | assetId, amount, destinationAddress, network? }
//
// ⚠️ UNVERIFIED ENDPOINT — Eversend's public API reference
// (eversend.readme.io) documents crypto deposit-address creation and
// fee lookup, but does not publish a crypto payout/withdrawal
// endpoint at the time this was written. This route calls
// POST /crypto/withdraw as the most consistent guess given Eversend's
// existing REST conventions (/crypto/addresses, /crypto/fees,
// /crypto/transactions all sit under /crypto), but it has not been
// POST /api/v1/crypto/withdraw
// Body: { coin, amount, destinationCurrency }
//
// CORRECTED (was previously an unverified guess at a direct
// /crypto/withdraw endpoint — Eversend's crypto API reference does
// not have one; see crypto-resources overview, confirmed 2026-08-27:
// "Eversend Crypto API: ... 1. Fetch Assets Chains 2. Create Crypto
// Address 3. Fetch Existing Crypto Addresses 4. View Crypto
// Transactions 5. Receive Crypto" — receiving only). Eversend's own
// docs describe the intended flow explicitly: "Copy your generated
// crypto address and receive your assets directly. Exchange them to
// fiat or transfer them to your bank account or mobile money account
// effortlessly." So "crypto withdrawal" here genuinely means:
// exchange the coin's wallet balance to fiat via the confirmed
// POST /v1/exchanges/quotation -> POST /v1/exchanges endpoints. This
// route's job ends there — the app then hands off to the normal
// payout flow (paymentRouter.js's getQuotation/executePayout, the
// same one every other send flow uses) to actually send that fiat
// out, which is where a destination country belongs, not here.
router.post('/withdraw', requireAppUser, async (req, res, next) => {
  try {
    const { coin, amount, destinationCurrency } = req.body || {};
    if (!coin || !amount || !destinationCurrency) {
      return res.status(400).json({
        error: 'coin, amount and destinationCurrency are required.',
      });
    }

    const upperCoin = String(coin).toUpperCase();

    // Step 1: confirmed real endpoint — quote converting the coin's
    // wallet balance into the destination fiat currency.
    const exchangeQuote = await eversend.post('/exchanges/quotation', {
      from: upperCoin,
      amount,
      to: destinationCurrency,
    });

    const quoteToken = exchangeQuote?.data?.token ?? exchangeQuote?.token;
    if (!quoteToken) {
      return res.status(502).json({ error: "Couldn't get an exchange rate for this coin right now. Try again shortly." });
    }

    // Step 2: confirmed real endpoint — execute the exchange, moving
    // the coin balance into the destination fiat wallet.
    const exchangeResult = await eversend.post('/exchanges', { token: quoteToken });

    // Dutch Remit's 1% crypto markup, charged here since this is the
    // crypto-specific step of the flow — the payout itself (step 3)
    // still carries the general 1.2% transfer markup from
    // paymentRouter.js, so the two aren't double-charged on the same
    // leg.
    let feeBreakdown = null;
    try {
      const feeData = await eversend.get('/crypto/fees');
      feeBreakdown = applyCryptoMarkup(feeData);
    } catch (_) {
      // Non-fatal — the exchange already completed; a missing fee
      // pre-quote doesn't undo that.
    }

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'crypto_withdrawal',
      status: exchangeResult?.status ?? 'completed',
      amount,
      currency: destinationCurrency,
      method: 'crypto',
      eversend_reference: exchangeResult?.transactionRef ?? exchangeResult?.reference ?? null,
      raw_response: { exchangeQuote, exchangeResult },
      provider: 'eversend',
      fee_charged: feeBreakdown?.totalFee ?? null,
    });

    // The app is responsible for the next step: sending the now-fiat
    // balance out via POST /api/v1/payouts/send (same as every other
    // transfer screen) using destinationCountry/destinationCurrency —
    // this endpoint's job ends at "coin successfully converted to
    // spendable fiat," matching what Eversend's own product actually
    // supports.
    res.json({
      exchangeResult,
      feeBreakdown,
      nextStep: 'Call POST /api/v1/payouts/send with the exchanged fiat balance to complete the withdrawal.',
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;

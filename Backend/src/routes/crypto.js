const express = require('express');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');

const router = express.Router();

// Powers the "Crypto" method in top_up_screen.dart / withdraw_screen.dart.

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
// Body (flexible): { coin } — e.g. 'USDT', 'BTC', 'ETH' — or the raw
// Eversend { chain, asset } if you already know your enabled chains.
// A friendly { coin } is mapped to sensible chain/asset defaults; on
// success we always return a normalized { address, network, asset }
// alongside the raw Eversend payload so the app doesn't depend on
// Eversend's exact response shape.
router.post('/addresses', requireAppUser, async (req, res, next) => {
  try {
    let body = req.body || {};
    if (body.coin && !body.asset) {
      // Map a friendly coin to Eversend chain/asset. USDT commonly lives
      // on TRON (TRC20) or ETH (ERC20); default to TRC20 for lower fees.
      const coin = String(body.coin).toUpperCase();
      const map = {
        USDT: { asset: 'USDT', chain: 'TRON' },
        BTC: { asset: 'BTC', chain: 'BITCOIN' },
        ETH: { asset: 'ETH', chain: 'ETHEREUM' },
      };
      body = map[coin] || { asset: coin, chain: coin };
    }

    const data = await eversend.post('/crypto/addresses', body);

    const addr =
      data?.address ??
      data?.data?.address ??
      data?.walletAddress ??
      data?.data?.walletAddress ??
      null;
    const network = data?.chain ?? data?.data?.chain ?? body.chain ?? null;
    const asset = data?.asset ?? data?.data?.asset ?? body.asset ?? null;

    res.json({ address: addr, network, asset, raw: data });
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

module.exports = router;

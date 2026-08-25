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
// Body: { chain, asset } (exact field names depend on which asset
// chains are active on your account — GET /crypto/addresses first to
// see the shape Eversend expects for your enabled chains).
router.post('/addresses', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.post('/crypto/addresses', req.body);
    res.json(data);
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

const express = require('express');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');

const router = express.Router();

// GET /api/v1/wallets — every fiat + crypto balance the business
// account holds. Powers the wallet/balance display across Home,
// Wallet and the Send hub.
router.get('/', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.get('/wallets');
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/wallets/:currency — a single wallet's balance, e.g. USD.
router.get('/:currency', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.get(`/wallets/${req.params.currency}`);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;

const express = require('express');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { getBalanceUsd } = require('../walletLedger');

const router = express.Router();

// GET /api/v1/wallets/my-balance — the real, per-user tracked
// balance from wallet_ledger, in USD. This is the number the app
// should show as "your balance" everywhere (Home screen, Wallet,
// Send hub) — NOT GET /api/v1/wallets below, which returns the
// entire pooled Eversend BUSINESS account balance shared across
// every user of this app, not any individual user's own money.
//
// This was the real, confirmed cause of "I did a real deposit but my
// balance doesn't update the way I expect": the app has always
// called GET /api/v1/wallets and shown that number as "your"
// balance, even though wallet_ledger (built this session
// specifically to track each user's own balance correctly) was never
// actually read back out anywhere — every debit/credit check used it
// correctly internally, but nothing ever displayed it. A user's real
// deposit genuinely landed in the pooled Eversend wallet (which is
// why the money is "presently" in the business's real Eversend
// account), and wallet_ledger was genuinely credited correctly by
// the webhook handler — but the screen showing "your balance" was
// reading a completely different, shared number the whole time.
router.get('/my-balance', requireAppUser, async (req, res, next) => {
  try {
    const balanceUsd = await getBalanceUsd(req.user.id);
    res.json({ balanceUsd, currency: 'USD' });
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/wallets — every fiat + crypto balance the business
// account holds — the shared pooled balance across every user, NOT
// any one user's own money. Kept for anything that genuinely needs
// the business-level view (e.g. admin/ops tooling), but the app's
// own "your balance" display should use GET /wallets/my-balance
// above instead.
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

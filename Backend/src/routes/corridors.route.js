const express = require('express');
const {
  EVERSEND_PAYOUT_COUNTRIES,
  AFRICAN_PAYOUT_COUNTRIES,
  MOMO_BENEFICIARY_COUNTRIES,
} = require('../corridors');

const router = express.Router();

// GET /api/v1/corridors — the confirmed corridor reference data the
// Send Abroad hub's tabs (Global Transfer, Diaspora to Africa, Africa
// to Africa, Quick Transfer) should build their country pickers from,
// instead of hardcoding country lists in the Flutter app that can
// drift out of sync with what's actually enabled on Eversend.
router.get('/', (req, res) => {
  res.json({
    payoutCountries: EVERSEND_PAYOUT_COUNTRIES,
    africanPayoutCountries: AFRICAN_PAYOUT_COUNTRIES,
    momoBeneficiaryCountries: MOMO_BENEFICIARY_COUNTRIES,
  });
});

module.exports = router;

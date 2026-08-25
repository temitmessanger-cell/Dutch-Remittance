const express = require('express');
const { eversend } = require('../eversendClient');
const { getQuotation } = require('../paymentRouter');

const router = express.Router();

// A wallet-to-wallet exchange doesn't carry an explicit "fee" field
// from the provider the way a payout quotation does — the margin on
// an FX conversion is conventionally taken as a small spread baked
// into the rate itself (this is how every remittance/FX product
// prices conversions; see PRICING.md at the repo root for the full
// breakdown). 0.5% here, applied to whichever amount/converted field
// the provider's response actually uses — kept small and undisclosed
// as a separate line item, same as the payout markup.
const EXCHANGE_MARKUP_RATE = 0.005;

function applyExchangeMarkup(providerData) {
  const payload = providerData?.data ?? providerData ?? {};
  const adjusted = { ...payload };
  for (const key of ['amount', 'convertedAmount', 'destinationAmount', 'toAmount']) {
    if (typeof payload[key] === 'number') {
      adjusted[key] = +(payload[key] * (1 - EXCHANGE_MARKUP_RATE)).toFixed(2);
    }
  }
  return { ...providerData, data: adjusted };
}

// POST /api/v1/rates/quotation — the ONE quotation endpoint every
// Send Abroad tab (Global Transfer, Diaspora to Africa, Africa to
// Africa, Quick Transfer) and Withdrawal should call. Picks Eversend
// or Klasha automatically based on the destination currency (see
// paymentRouter.js / corridors.js) so the app never has to know or
// care which provider is behind a given corridor.
router.post('/quotation', async (req, res, next) => {
  try {
    const { sourceWallet, amount, amountType, type, destinationCountry, destinationCurrency } =
      req.body || {};
    if (!sourceWallet || !amount || !destinationCountry || !destinationCurrency) {
      return res.status(400).json({
        error: 'sourceWallet, amount, destinationCountry and destinationCurrency are required.',
      });
    }
    const result = await getQuotation({
      sourceWallet, amount, amountType, type, destinationCountry, destinationCurrency,
    });
    res.json(result);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/rates/exchange-quotation
// Body: { source: "USD", destination: "UGX", amount: 100 }
// This is the *wallet-to-wallet exchange* quote (converting a
// balance you already hold from one currency to another) — distinct
// from a payout quotation, which prices sending money out to a
// beneficiary. Public reference data, no user session required.
router.post('/exchange-quotation', async (req, res, next) => {
  try {
    const { source, destination, amount } = req.body || {};
    if (!source || !destination || !amount) {
      return res
        .status(400)
        .json({ error: 'source, destination and amount are required.' });
    }
    const data = await eversend.post('/exchanges/quotation', {
      source,
      destination,
      amount,
    });
    res.json(applyExchangeMarkup({ data }));
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/rates/payout-quotation
// Body: { sourceWallet, amount, amountType: "SOURCE"|"DESTINATION",
//         type: "momo"|"bank", destinationCountry, destinationCurrency }
// This is the number that powers every "You send / They receive"
// card across Global Transfer, Diaspora to Africa, Africa to Africa
// and Quick Transfer — the live rate + fee, locked into a short-lived
// quotation token used to actually execute the payout.
router.post('/payout-quotation', async (req, res, next) => {
  try {
    const {
      sourceWallet,
      amount,
      amountType = 'SOURCE',
      type = 'momo',
      destinationCountry,
      destinationCurrency,
    } = req.body || {};

    if (!sourceWallet || !amount || !destinationCountry || !destinationCurrency) {
      return res.status(400).json({
        error:
          'sourceWallet, amount, destinationCountry and destinationCurrency are required.',
      });
    }

    const data = await eversend.post('/payouts/quotation', {
      sourceWallet,
      amount,
      amountType,
      type,
      destinationCountry,
      destinationCurrency,
    });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/rates/eversend-wallet-quotation
// Body: { sourceWallet, amount, amountType, phone }
// Quote for sending straight to another Eversend user's balance
// (Dutch Remit's "Invite" / friends-on-Dutch-Remit flow).
router.post('/eversend-wallet-quotation', async (req, res, next) => {
  try {
    const { sourceWallet, amount, amountType = 'SOURCE', phone } = req.body || {};
    if (!sourceWallet || !amount || !phone) {
      return res
        .status(400)
        .json({ error: 'sourceWallet, amount and phone are required.' });
    }
    const data = await eversend.post('/payouts/quotation/eversend', {
      sourceWallet,
      amount,
      amountType,
      phone,
    });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;

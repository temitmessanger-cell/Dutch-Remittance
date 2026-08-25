const express = require('express');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');
const { MOMO_BENEFICIARY_COUNTRIES } = require('../corridors');

const router = express.Router();

// POST /api/v1/beneficiaries/check-eversend-account
// Body: { phone } or { email } — only one is used if both are sent.
router.post('/check-eversend-account', requireAppUser, async (req, res, next) => {
  try {
    const { phone, email } = req.body || {};
    const data = await eversend.post('/beneficiaries/accounts/eversend', {
      ...(phone ? { phone } : {}),
      ...(email ? { email } : {}),
    });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.get('/', requireAppUser, async (req, res, next) => {
  try {
    const page = Number(req.query.page) || 1;
    const limit = Number(req.query.limit) || 20;
    const data = await eversend.get('/beneficiaries', { page, limit });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.get('/:id', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.get(`/beneficiaries/${req.params.id}`);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/beneficiaries
// Body: array of beneficiary objects, e.g.
//   [{ firstName, lastName, country, phoneNumber, isBank, isMomo }]
// For momo beneficiaries, `country` must be one of
// MOMO_BENEFICIARY_COUNTRIES (confirmed live momo payout corridors,
// including Cameroon via country: "CM" — see corridors.js). Also
// mirrors each created beneficiary into Supabase so the Recipient
// tab loads instantly from cache while Eversend is the source of truth.
router.post('/', requireAppUser, async (req, res, next) => {
  try {
    const beneficiaries = Array.isArray(req.body) ? req.body : [req.body];

    for (const b of beneficiaries) {
      if (b.isMomo && !MOMO_BENEFICIARY_COUNTRIES.includes(b.country)) {
        return res.status(400).json({
          error: `${b.country} is not a confirmed live momo payout country. Supported: ${MOMO_BENEFICIARY_COUNTRIES.join(', ')}`,
        });
      }
    }

    const data = await eversend.post('/beneficiaries', beneficiaries);

    const rows = beneficiaries.map((b) => ({
      user_id: req.user.id,
      eversend_beneficiary_id: data?.id ?? data?.data?.id ?? null,
      first_name: b.firstName,
      last_name: b.lastName,
      country: b.country,
      phone_number: b.phoneNumber ?? null,
      is_bank: !!b.isBank,
      is_momo: !!b.isMomo,
      bank_name: b.bankName ?? null,
      bank_account_number: b.bankAccountNumber ?? null,
      bank_code: b.bankCode ?? null,
    }));
    await supabaseAdmin.from('beneficiaries').insert(rows);

    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.patch('/:id', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.patch(`/beneficiaries/${req.params.id}`, req.body);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.delete('/:id', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.delete(`/beneficiaries/${req.params.id}`);
    await supabaseAdmin
      .from('beneficiaries')
      .delete()
      .eq('eversend_beneficiary_id', req.params.id)
      .eq('user_id', req.user.id);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;

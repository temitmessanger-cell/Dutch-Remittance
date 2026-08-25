const express = require('express');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');

const router = express.Router();

// GET /api/v1/transactions?page=&limit=
// Merges Eversend's own transaction log with this user's rows in
// Supabase (see supabase/schema.sql -> public.transactions), the
// same "don't block the screen if one source fails" pattern already
// used on the Flutter side (all_transaction_activities_screen.dart).
// GET /api/v1/transactions?page=&limit=
// Every transaction this user has ever made is already recorded in
// Supabase (see supabase/schema.sql -> public.transactions) at the
// moment it happens — every payout, card fund/withdraw, transfer,
// etc. writes a row here with user_id set (see payouts.js, cards.js).
// SECURITY: this used to also merge in eversend.get('/transactions'),
// but that call returns Eversend's entire merchant-wide transaction
// log — every Dutch Remit user's transactions, not just the caller's,
// since Eversend has no concept of Dutch Remit's individual end
// users. That leaked other users' transaction history (amounts,
// recipients, everything) to any authenticated caller. Supabase alone
// is both sufficient and correctly scoped, so it's now the only
// source here.
router.get('/', requireAppUser, async (req, res, next) => {
  const page = Number(req.query.page) || 1;
  const limit = Number(req.query.limit) || 20;

  const { data, error } = await supabaseAdmin
    .from('transactions')
    .select('*')
    .eq('user_id', req.user.id)
    .order('created_at', { ascending: false })
    .range((page - 1) * limit, page * limit - 1);

  if (error) return res.status(500).json({ error: 'Could not load transactions.' });

  res.json({ transactions: data || [] });
});

// GET /api/v1/transactions/:id
// SECURITY: :id here is Eversend's own transaction reference, and
// Eversend's lookup endpoint isn't scoped per end-user — so this must
// confirm the reference belongs to req.user.id in our own ledger
// before ever calling Eversend, or any authenticated user could read
// any other user's transaction (amount, counterparty, status) just by
// guessing/enumerating a reference.
router.get('/:id', requireAppUser, async (req, res, next) => {
  try {
    const { data: owned, error } = await supabaseAdmin
      .from('transactions')
      .select('id')
      .eq('eversend_reference', req.params.id)
      .eq('user_id', req.user.id)
      .maybeSingle();

    if (error) return res.status(500).json({ error: 'Could not verify transaction ownership.' });
    if (!owned) return res.status(404).json({ error: 'Transaction not found.' });

    const data = await eversend.get(`/transactions/${req.params.id}`);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;

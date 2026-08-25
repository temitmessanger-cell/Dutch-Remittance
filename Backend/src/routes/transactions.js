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
router.get('/', requireAppUser, async (req, res, next) => {
  const page = Number(req.query.page) || 1;
  const limit = Number(req.query.limit) || 20;

  const [eversendResult, supabaseResult] = await Promise.allSettled([
    eversend.get('/transactions', { page, limit }),
    supabaseAdmin
      .from('transactions')
      .select('*')
      .eq('user_id', req.user.id)
      .order('created_at', { ascending: false })
      .range((page - 1) * limit, page * limit - 1),
  ]);

  if (eversendResult.status === 'rejected' && supabaseResult.status === 'rejected') {
    return next(eversendResult.reason);
  }

  res.json({
    eversendTransactions:
      eversendResult.status === 'fulfilled' ? eversendResult.value : [],
    localTransactions:
      supabaseResult.status === 'fulfilled' ? supabaseResult.value.data : [],
  });
});

router.get('/:id', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.get(`/transactions/${req.params.id}`);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;

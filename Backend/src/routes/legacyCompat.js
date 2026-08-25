const express = require('express');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');

const router = express.Router();

/**
 * The current Flutter app (see lib/utilities/make_api_request.dart and
 * lib/resources/api_constants.dart) already calls a handful of legacy
 * paths shaped like `/Dutch Remit/v1/...` against ApiConstants.baseUrl.
 * These routes exist so you can point ApiConstants.baseUrl at this
 * backend and the app works immediately, without a Flutter rewrite —
 * now backed by real data (Supabase) instead of a dead/removed
 * third-party host.
 */

// GET /Dutch Remit/v1/all-transactions
// Used by all_transaction_activities_screen.dart, all_contacts.dart.
router.get('/all-transactions', requireAppUser, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('transactions')
    .select('*')
    .eq('user_id', req.user.id)
    .order('created_at', { ascending: false })
    .limit(100);

  if (error) {
    return res.json({ apiRequestError: 'Could not load transactions.' });
  }

  const transactions = (data || []).map((t) => ({
    transactionMemberName: t.beneficiary_id
      ? `Transfer (${t.currency || ''})`
      : `${t.type} · ${t.method || ''}`.trim(),
    transactionAmount: t.amount != null ? String(t.amount) : '0',
    transactionType: t.type === 'deposit' ? 'credit' : 'debit',
    transactionDate: t.created_at,
    status: t.status,
    currency: t.currency,
    provider: t.provider,
  }));

  res.json({ transactions });
});

// GET /Dutch Remit/v1/available-cards
// Used by database/cards_storage.dart. NOTE: this reflects cards
// already on file in Supabase — see the "card linking" caveat in
// README.md before wiring a real "submit card details" flow to write
// here; raw card numbers/CVVs must never be sent to or stored by this
// backend.
router.get('/available-cards', requireAppUser, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('cards')
    .select('*')
    .eq('user_id', req.user.id)
    .order('created_at', { ascending: false });

  if (error) return res.json({ apiRequestError: 'Could not load cards.' });

  res.json({ availableCards: data || [] });
});

// POST /Dutch Remit/v2/execute-transaction
// Body: { transactionReceipt: { transactionMemberName, transactionAmount,
//         transactionType, ... } } — used for the "pay a contact or
// business" flow (fund_transfer_screen/transaction_processing_screen.dart).
// This records the transaction against the signed-in user in Supabase;
// it does not itself move money on Eversend/Klasha (that's what the
// unified /api/v1/payouts/send and /api/v1/payouts/eversend routes do
// for beneficiary/wallet sends specifically) — a same-app "request"
// or ledger entry is what this endpoint has always represented here.
router.post('/execute-transaction', requireAppUser, async (req, res) => {
  const receipt = req.body?.transactionReceipt;
  if (!receipt || !receipt.transactionAmount) {
    return res.json({ error: 'A transaction receipt is required.' });
  }

  const amount = parseFloat(receipt.transactionAmount);
  if (isNaN(amount) || amount <= 0) {
    return res.json({ error: 'Invalid transaction amount.' });
  }

  const { data, error } = await supabaseAdmin
    .from('transactions')
    .insert({
      user_id: req.user.id,
      type: receipt.transactionType === 'credit' ? 'deposit' : 'payout',
      status: 'completed',
      amount,
      method: 'internal',
      raw_response: receipt,
    })
    .select()
    .single();

  if (error) {
    return res.json({ error: 'Could not record the transaction.' });
  }

  res.json({ status: 'success', transaction: data, transactionReceipt: receipt });
});

module.exports = router;

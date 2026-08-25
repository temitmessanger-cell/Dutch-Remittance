const express = require('express');
const crypto = require('crypto');
const { supabaseAdmin } = require('../supabaseClient');

const router = express.Router();

// POST /api/v1/webhooks/eversend
// Configure this URL in the Eversend dashboard (Settings ->
// Developers -> Webhook) so transaction status changes (collection
// settled, payout delivered/failed, etc.) update Supabase in real
// time instead of the app having to poll.
//
// IMPORTANT: this route needs the *raw* request body to verify the
// signature, so it's mounted with express.raw() in server.js rather
// than the global express.json() parser.
router.post('/eversend', async (req, res) => {
  const signature = req.headers['x-eversend-signature'];
  const secret = process.env.EVERSEND_WEBHOOK_SECRET;

  if (!secret || secret.startsWith('replace_after')) {
    console.warn('EVERSEND_WEBHOOK_SECRET is not configured — rejecting webhook.');
    return res.status(500).send('Webhook secret not configured.');
  }

  const expectedHash = crypto
    .createHmac('sha512', secret)
    .update(req.body) // raw Buffer, per Eversend's docs
    .digest('hex');

  if (expectedHash !== signature) {
    return res.status(401).send('Invalid signature.');
  }

  let payload;
  try {
    payload = JSON.parse(req.body.toString('utf8'));
  } catch (e) {
    return res.status(400).send('Invalid JSON payload.');
  }

  await supabaseAdmin.from('webhook_events').insert({
    source: 'eversend',
    event_type: payload.event ?? payload.type ?? 'unknown',
    payload,
  });

  // Best-effort: if the payload references a transaction we already
  // recorded (by Eversend's own reference), keep it in sync.
  const reference =
    payload.transactionRef || payload.reference || payload.data?.transactionRef;
  if (reference) {
    await supabaseAdmin
      .from('transactions')
      .update({ status: payload.status || payload.data?.status || 'updated' })
      .eq('eversend_reference', reference);
  }

  res.status(200).send('ok');
});

// POST /api/v1/webhooks/klasha
// Configure in the Klasha dashboard. Klasha's webhook signing isn't
// publicly documented the way Eversend's HMAC scheme is (their docs
// cover request-payload encryption, not webhook verification) — this
// logs every event unconditionally and syncs matching transactions,
// same as the Eversend handler, but SKIPS signature verification.
// If Klasha's dashboard shows a signing secret/header when you set
// the webhook up, tell me what it's called and I'll add verification
// here to match — right now this endpoint trusts any caller, which
// is fine for logging but shouldn't be relied on for anything
// security-sensitive until that's confirmed.
router.post('/klasha', async (req, res) => {
  let payload;
  try {
    payload = JSON.parse(req.body.toString('utf8'));
  } catch (e) {
    return res.status(400).send('Invalid JSON payload.');
  }

  await supabaseAdmin.from('webhook_events').insert({
    source: 'klasha',
    event_type: payload.event ?? payload.type ?? 'unknown',
    payload,
  });

  const reference = payload.txRef || payload.reference || payload.data?.txRef;
  if (reference) {
    await supabaseAdmin
      .from('transactions')
      .update({ status: payload.status || payload.data?.status || 'updated' })
      .eq('eversend_reference', reference);
  }

  res.status(200).send('ok');
});

module.exports = router;

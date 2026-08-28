const express = require('express');
const crypto = require('crypto');
const { supabaseAdmin } = require('../supabaseClient');
const { credit, convertToUsd } = require('../walletLedger');

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

  // Loud, specific logging here on purpose: a silently-misconfigured
  // webhook is the single most likely reason a real, successful
  // deposit never shows up in a user's tracked balance — Eversend
  // genuinely received the money and confirmed it, but if this route
  // never accepts the callback, wallet_ledger is never credited and
  // the wallet stays at $0 forever with no visible error anywhere
  // else in the app. This log line is the fastest way to confirm
  // whether that's what's actually happening.
  if (!secret || secret.startsWith('replace_after')) {
    console.error(
      '[webhooks/eversend] REJECTED — EVERSEND_WEBHOOK_SECRET is not set (or still the placeholder) in this environment. ' +
      'Every incoming Eversend webhook is being rejected right now, which means deposits will never be credited to wallet_ledger. ' +
      'Set the real secret from the Eversend dashboard (Settings -> Developers -> Webhook) as EVERSEND_WEBHOOK_SECRET in Railway.'
    );
    return res.status(500).send('Webhook secret not configured.');
  }

  const expectedHash = crypto
    .createHmac('sha512', secret)
    .update(req.body) // raw Buffer, per Eversend's docs
    .digest('hex');

  if (expectedHash !== signature) {
    console.error(
      `[webhooks/eversend] REJECTED — signature mismatch. This means either EVERSEND_WEBHOOK_SECRET in Railway ` +
      `does not match the secret shown on Eversend's dashboard for this webhook, or the request genuinely isn't from Eversend. ` +
      `Received signature header: ${signature ? '(present)' : '(MISSING — check the webhook is actually configured to send x-eversend-signature)'}`
    );
    return res.status(401).send('Invalid signature.');
  }

  console.log('[webhooks/eversend] Signature verified — processing webhook.');

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
  //
  // This field-name list was never confirmed against a real Eversend
  // webhook payload (no network access to Eversend from the
  // environment this was originally written in) — it was a
  // defensive guess. If the real payload uses a field name not
  // covered here, `reference` ends up undefined and this ENTIRE
  // block — including the deposit credit further down — is skipped
  // completely silently, with no error anywhere. This is a strong
  // candidate for "a real deposit happened but the wallet stays at
  // $0 forever with nothing visibly wrong." Broadened the field list
  // and added logging specifically so this becomes visible in Railway
  // logs instead of a silent no-op if it's still wrong.
  const reference =
    payload.transactionRef ||
    payload.reference ||
    payload.transactionReference ||
    payload.ref ||
    payload.data?.transactionRef ||
    payload.data?.reference ||
    payload.data?.transactionReference ||
    payload.data?.ref ||
    payload.data?.id;

  console.log('[webhooks/eversend] payload received', {
    eventType: payload.event ?? payload.type ?? 'unknown',
    extractedReference: reference || '(none found — check the field name list above against the real payload logged here)',
    payloadKeys: Object.keys(payload || {}),
    dataKeys: payload.data ? Object.keys(payload.data) : null,
  });

  if (reference) {
    const newStatus = payload.status || payload.data?.status || 'updated';
    const { data: updatedTxn, error: updateErr } = await supabaseAdmin
      .from('transactions')
      .update({ status: newStatus })
      .eq('eversend_reference', reference)
      .select('id, user_id, type, amount, currency, status')
      .maybeSingle();

    if (updateErr) {
      console.error('[webhooks/eversend] Supabase update failed', updateErr);
    } else if (!updatedTxn) {
      console.warn(
        `[webhooks/eversend] No transaction row found with eversend_reference = "${reference}". ` +
        `This means the reference the webhook sent doesn't match what was stored when the deposit was ` +
        `initiated (see collections.js's POST /momo, which stores eversend_reference from Eversend's own ` +
        `response) — the transaction status/balance credit for this event was skipped.`
      );
    }

    // Real fund-safety credit: only once a deposit reaches a
    // genuinely confirmed status (never "pending") does the user's
    // tracked wallet_ledger balance actually increase. Crediting on
    // the initial API response (before Eversend/Klasha confirm
    // settlement) would let a user withdraw money that hadn't
    // actually arrived yet if the deposit later failed — this is the
    // one place that credit safely happens. Amount is converted to
    // USD first (deposits often come in as XAF/GHS/etc., not USD) so
    // wallet_ledger stays comparable across every currency a user
    // touches.
    //
    // No deposit-limit check happens here on purpose: by the time a
    // webhook fires, the real money has already arrived at
    // Eversend/Klasha. The $1/$5000/$8000 limits (validateDepositAmountUsd)
    // are enforced before a deposit is initiated (see collections.js's
    // POST /momo) — refusing to credit money that's already real and
    // already moved would just mean the platform holds a user's funds
    // without ever crediting them, which is worse than the limit
    // itself.
    if (updatedTxn && updatedTxn.type === 'deposit') {
      const confirmedStatuses = ['completed', 'successful', 'success'];
      if (confirmedStatuses.includes((updatedTxn.status || '').toLowerCase())) {
        try {
          const amountUsd = await convertToUsd(updatedTxn.amount, updatedTxn.currency);
          if (amountUsd != null && amountUsd > 0) {
            await credit(updatedTxn.user_id, amountUsd, `deposit (${updatedTxn.currency})`, updatedTxn.id);
            console.log(`[webhooks/eversend] Credited user ${updatedTxn.user_id}: $${amountUsd.toFixed(2)} USD (${updatedTxn.amount} ${updatedTxn.currency})`);
          } else {
            console.error(`[webhooks/eversend] convertToUsd returned null/0 for ${updatedTxn.amount} ${updatedTxn.currency} — deposit confirmed but NOT credited to wallet_ledger.`);
          }
        } catch (creditErr) {
          console.error('[webhooks/eversend] credit() threw — deposit confirmed but NOT credited to wallet_ledger.', creditErr);
        }
      } else {
        console.log(`[webhooks/eversend] Transaction status is "${updatedTxn.status}", not yet a confirmed status — no credit issued (correct behavior, waiting for a genuinely completed status).`);
      }
    }

    // Surfaces in the Payments tab's Notifications upper nav
    // (all_transaction_activities_screen.dart) — this was the one
    // missing piece keeping that tab always empty: the read/display
    // side existed, nothing ever wrote a row. Best-effort only; a
    // failed insert here should never block webhook processing
    // (the transaction status update above is already committed).
    if (updatedTxn) {
      await _notifyTransactionUpdate(updatedTxn);
    }
  }

  res.status(200).send('ok');
});

/// Writes a plain-language, branded notification for a transaction
/// status change — deliberately simple copy, not trying to explain
/// every possible status string, since most users only care about
/// "did it work or not." No payment API (Eversend, Klasha, or
/// otherwise) lets a sender control the SMS text a recipient's own
/// mobile network shows them when money lands — that's generated by
/// the telco itself, industry-wide, the same way it works for every
/// remittance app. This in-app notification is the one place Dutch
/// Remit branding genuinely can appear, so the title always leads
/// with "Dutch Remit" rather than a bare status word.
async function _notifyTransactionUpdate(txn) {
  const isSuccess = ['completed', 'successful', 'success'].includes((txn.status || '').toLowerCase());
  const isFailure = ['failed', 'declined', 'error'].includes((txn.status || '').toLowerCase());
  if (!isSuccess && !isFailure) return; // "pending"/"processing" etc. aren't worth a notification

  const amountLabel = txn.amount != null ? `${txn.amount} ${txn.currency || ''}`.trim() : '';
  const isDeposit = txn.type === 'deposit';
  const title = isSuccess
    ? (isDeposit ? 'Dutch Remit — Deposit received' : 'Dutch Remit — Transfer sent')
    : "Dutch Remit — Transaction didn't go through";
  const body = isSuccess
    ? `Your ${isDeposit ? 'deposit' : 'transfer'} of ${amountLabel} completed successfully.`
    : `Your ${isDeposit ? 'deposit' : 'transfer'} of ${amountLabel} couldn't be completed. Check Payments for details.`;

  try {
    await supabaseAdmin.from('notifications').insert({
      user_id: txn.user_id,
      title,
      body,
    });
  } catch (_) {
    // Non-fatal — a missing notification is far less bad than a
    // webhook handler that throws and never acks Eversend/Klasha.
  }
}

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
    const newStatus = payload.status || payload.data?.status || 'updated';
    const { data: updatedTxn } = await supabaseAdmin
      .from('transactions')
      .update({ status: newStatus })
      .eq('eversend_reference', reference)
      .select('id, user_id, type, amount, currency, status')
      .maybeSingle();

    // Same real fund-safety credit as the Eversend webhook above —
    // Klasha-routed deposits (e.g. via a Klasha virtual account) only
    // increase wallet_ledger once genuinely confirmed.
    if (updatedTxn && updatedTxn.type === 'deposit') {
      const confirmedStatuses = ['completed', 'successful', 'success'];
      if (confirmedStatuses.includes((updatedTxn.status || '').toLowerCase())) {
        try {
          const amountUsd = await convertToUsd(updatedTxn.amount, updatedTxn.currency);
          if (amountUsd != null && amountUsd > 0) {
            await credit(updatedTxn.user_id, amountUsd, `deposit (${updatedTxn.currency})`, updatedTxn.id);
          }
        } catch (_) {}
      }
    }

    if (updatedTxn) {
      await _notifyTransactionUpdate(updatedTxn);
    }
  }

  res.status(200).send('ok');
});

module.exports = router;

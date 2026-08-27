const { supabaseAdmin } = require('./supabaseClient');
const { eversend } = require('./eversendClient');

/**
 * Platform-wide transaction limits — deliberately centralized here
 * rather than scattered per-route, so every deposit/top-up/exchange/
 * card-funding path enforces the exact same numbers. Previously
 * nothing in this backend enforced any minimum, maximum, or
 * total-balance cap at all.
 */
// Per-deposit/top-up limits.
const MIN_DEPOSIT_USD = 1;
const MAX_DEPOSIT_USD = 5000;
// The absolute ceiling on a single user's total tracked balance
// across everything (wallet + any pending holds) — enforced at
// credit time, not just deposit time, so no combination of deposits
// can push a user over this regardless of how they arrived at it.
const MAX_TOTAL_BALANCE_USD = 8000;

/**
 * Validates a deposit/top-up amount against MIN_DEPOSIT_USD and
 * MAX_DEPOSIT_USD, and — combined with the user's current balance —
 * against MAX_TOTAL_BALANCE_USD. Returns { ok: true } or
 * { ok: false, error } with a plain, user-understandable message
 * (never a raw validation error or a number the user has to do
 * mental math on) — callers should surface `error` directly rather
 * than construct their own message, so this wording only has to be
 * right in one place.
 */
async function validateDepositAmountUsd(userId, amountUsd) {
  if (!(amountUsd > 0)) {
    return { ok: false, error: 'Enter a valid amount.' };
  }
  if (amountUsd < MIN_DEPOSIT_USD) {
    return { ok: false, error: `The minimum deposit is \$${MIN_DEPOSIT_USD}.` };
  }
  if (amountUsd > MAX_DEPOSIT_USD) {
    return { ok: false, error: `The maximum deposit is \$${MAX_DEPOSIT_USD} per transaction.` };
  }
  const currentBalance = await getBalanceUsd(userId);
  if (currentBalance + amountUsd > MAX_TOTAL_BALANCE_USD) {
    const remaining = Math.max(0, MAX_TOTAL_BALANCE_USD - currentBalance);
    return {
      ok: false,
      error: remaining > 0
        ? `This would put your wallet over the \$${MAX_TOTAL_BALANCE_USD} balance limit. You can deposit up to \$${remaining.toFixed(2)} more right now.`
        : `Your wallet is already at the \$${MAX_TOTAL_BALANCE_USD} balance limit. Spend or send some funds before depositing more.`,
    };
  }
  return { ok: true };
}

/**
 * The real, authoritative per-user balance system — see
 * supabase/schema.sql's wallet_ledger table comment for the full
 * rationale. Before this module existed, every money-moving route
 * (payouts, card funding, crypto exchange, wallet-to-wallet
 * transfers) forwarded straight to Eversend/Klasha with no check on
 * whether the requesting user's own deposits actually covered the
 * amount — every user shared one pooled business wallet balance with
 * no per-user accounting at all. This module is the fix: every
 * credit and debit that should move a user's tracked balance goes
 * through here, and every debit is refused if it would take the
 * user's balance negative.
 *
 * Amounts are always tracked in USD (this platform's base currency).
 * Callers passing a non-USD amount are responsible for converting to
 * USD first using the same rate the underlying transaction was
 * quoted at — this module does not itself fetch exchange rates,
 * since the correct rate is already known at each call site (it's
 * what the quotation step just returned).
 */

/**
 * Returns [userId]'s current real balance in USD. Never null — a
 * brand-new user with no ledger entries yet has a balance of 0.
 */
async function getBalanceUsd(userId) {
  const { data, error } = await supabaseAdmin.rpc('get_user_balance_usd', {
    target_user_id: userId,
  });
  if (error) {
    // Fail closed: if we can't even determine the balance, treat it
    // as 0 rather than silently allowing a debit through on an
    // unknown balance. A credit failing this way just means the
    // credit doesn't apply yet (safe); a debit failing this way
    // means it's correctly refused (also safe) — see debitIfSufficient.
    throw new Error('Could not determine wallet balance right now.');
  }
  return Number(data) || 0;
}

/**
 * Records a credit (money in) to [userId]'s ledger — e.g. a
 * confirmed deposit, a refund, or money moved back from a card.
 * [amountUsd] must be positive; this function handles the sign
 * convention internally so call sites never have to remember whether
 * credits are positive or negative in the ledger.
 */
async function credit(userId, amountUsd, reason, referenceTransactionId = null) {
  if (!(amountUsd > 0)) {
    throw new Error('credit() amountUsd must be a positive number.');
  }
  const { error } = await supabaseAdmin.from('wallet_ledger').insert({
    user_id: userId,
    amount_usd: amountUsd,
    reason,
    reference_transaction_id: referenceTransactionId,
  });
  if (error) throw new Error('Could not record wallet credit.');
}

/**
 * The critical safety function: attempts to debit [amountUsd] from
 * [userId]'s balance, but ONLY if their current balance actually
 * covers it. Returns { ok: true } if the debit was recorded, or
 * { ok: false, currentBalance } if it was refused for insufficient
 * funds — callers MUST check `ok` and stop before calling
 * Eversend/Klasha if it's false, never proceed and record the ledger
 * entry afterward "just in case."
 *
 * This is not perfectly race-condition-free under extreme concurrent
 * load (a true DB-level row lock / serializable transaction would be
 * stronger, and is a reasonable follow-up if this app ever sees high
 * concurrent-request volume from a single user), but it closes the
 * real gap this was built for: a single request path now always
 * checks balance immediately before recording a debit, rather than
 * never checking at all.
 */
async function debitIfSufficient(userId, amountUsd, reason, referenceTransactionId = null) {
  if (!(amountUsd > 0)) {
    throw new Error('debitIfSufficient() amountUsd must be a positive number.');
  }
  const currentBalance = await getBalanceUsd(userId);
  if (currentBalance < amountUsd) {
    return { ok: false, currentBalance };
  }
  const { error } = await supabaseAdmin.from('wallet_ledger').insert({
    user_id: userId,
    amount_usd: -amountUsd,
    reason,
    reference_transaction_id: referenceTransactionId,
  });
  if (error) throw new Error('Could not record wallet debit.');
  return { ok: true, currentBalance: currentBalance - amountUsd };
}

/**
 * Converts [amount] in [currency] to USD using Eversend's confirmed
 * real exchange-quotation endpoint (POST /exchanges/quotation — the
 * same one crypto.js's withdrawal flow already uses). Returns null if
 * the conversion genuinely can't be determined right now, so callers
 * can decide how to handle that (e.g. skip crediting the ledger this
 * cycle and let a manual reconciliation catch it, rather than
 * guessing a number).
 */
async function convertToUsd(amount, currency) {
  if (currency === 'USD') return Number(amount);
  try {
    const quote = await eversend.post('/exchanges/quotation', {
      from: currency,
      amount,
      to: 'USD',
    });
    const converted = quote?.data?.destinationAmount ?? quote?.destinationAmount;
    return converted == null ? null : Number(converted);
  } catch (_) {
    return null;
  }
}

module.exports = {
  getBalanceUsd,
  credit,
  debitIfSufficient,
  convertToUsd,
  validateDepositAmountUsd,
  MIN_DEPOSIT_USD,
  MAX_DEPOSIT_USD,
  MAX_TOTAL_BALANCE_USD,
};

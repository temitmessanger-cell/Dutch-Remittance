const express = require('express');
const crypto = require('crypto');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');
const { debitIfSufficient, credit, MIN_DEPOSIT_USD, MAX_DEPOSIT_USD } = require('../walletLedger');

const router = express.Router();

// Full list of African ISO country codes (mirrors
// lib/utilities/african_country_data.dart client-side) — used only to
// decide the synthetic idType on the "proceed without KYC" path
// below, not for payout-corridor coverage (that's corridors.js).
const AFRICAN_COUNTRY_CODES = new Set([
  'AO', 'BF', 'BI', 'BJ', 'BW', 'CD', 'CF', 'CG', 'CI', 'CM', 'CV', 'DJ', 'DZ', 'EG',
  'ER', 'ET', 'GA', 'GH', 'GM', 'GN', 'GQ', 'GW', 'KE', 'KM', 'LR', 'LS', 'LY', 'MA',
  'MG', 'ML', 'MR', 'MU', 'MW', 'MZ', 'NA', 'NE', 'NG', 'RW', 'SC', 'SD', 'SL', 'SN',
  'SO', 'SS', 'SZ', 'TD', 'TG', 'TN', 'TZ', 'UG', 'ZA', 'ZM', 'ZW',
]);

// Card creation is never free: $3.50 one-time, or $1.10/month if the
// card is issued as an Eversend subscription card (isNonSubscription:
// false). "Proceed without KYC" adds a further $1.50 on top, either
// way — see POST / below for how these get charged and recorded.
const CARD_FEE_ONE_TIME = 3.5;
const CARD_FEE_MONTHLY = 1.1;
const KYC_SKIP_FEE = 1.5;

// Instant card: a flat $5.00 that issues a card immediately with no KYC
// and no document collection at all. Behind the scenes it reuses an
// existing Eversend cardholder (any the Dutch Remit merchant account
// already has), and if none is usable it auto-provisions a fresh
// cardholder with all fields populated synthetically — see the
// /instant route below. This fee is instead of (not on top of) the
// normal creation + KYC-skip fees.
const INSTANT_CARD_FEE = 5.0;

// Linking an existing card (as opposed to issuing a new Dutch-Remit
// card) charges a flat $2.10 retrieval fee — see POST /link below.
const CARD_LINK_FEE = 2.1;

// Generates a cardholder/document ID that is guaranteed unique against
// everything already in card_kyc_identities.id_number. A UUID collision
// is astronomically unlikely, but for money-linked identity records we
// verify against the DB rather than assume — retrying on the vanishing
// chance of a clash. Format: DR- + 12 uppercase hex chars, e.g.
// DR-9F3A1C7E2B04.
async function generateUniqueCardholderId() {
  for (let attempt = 0; attempt < 5; attempt++) {
    const candidate = `DR-${crypto.randomUUID().replace(/-/g, '').slice(0, 12).toUpperCase()}`;
    const { data, error } = await supabaseAdmin
      .from('card_kyc_identities')
      .select('id')
      .eq('id_number', candidate)
      .maybeSingle();
    // On a lookup error, fall back to a full UUID (still unique enough)
    // rather than blocking card issuance.
    if (error) return `DR-${crypto.randomUUID().toUpperCase()}`;
    if (!data) return candidate;
  }
  // Exhausted retries (effectively impossible) — use a full UUID.
  return `DR-${crypto.randomUUID().toUpperCase()}`;
}

// SECURITY: every route below that takes a :cardId param (view,
// fund, withdraw, freeze, unfreeze, terminate) MUST confirm the card
// actually belongs to req.user.id before calling Eversend or touching
// Supabase — Eversend's own card API is scoped to the whole Dutch
// Remit merchant account, not per end-user, so without this check any
// logged-in user could act on any other user's card just by knowing
// (or guessing/enumerating) its eversend_card_id. Returns the local
// `cards` row on success, or null (after already sending a 403/404)
// on failure — callers should `if (!card) return;`.
async function requireOwnedCard(req, res, cardId) {
  const { data: card, error } = await supabaseAdmin
    .from('cards')
    .select('id, eversend_card_id, user_id, status')
    .eq('eversend_card_id', cardId)
    .eq('user_id', req.user.id)
    .maybeSingle();

  if (error) {
    res.status(500).json({ error: 'Could not verify card ownership.' });
    return null;
  }
  if (!card) {
    // Deliberately the same 404 whether the card doesn't exist or
    // just isn't this user's — never confirm/deny another user's
    // card ID exists.
    res.status(404).json({ error: 'Card not found.' });
    return null;
  }
  return card;
}

/**
 * Real Eversend virtual card issuance — confirmed against their
 * published API reference (https://eversend.readme.io/reference/create-a-card,
 * .../create-a-card-user, .../fund-a-card), not guessed. Two steps:
 *
 *  1. POST /cards/user — a one-time KYC profile per person (name,
 *     email, phone, address, government ID). Required before a card
 *     can be issued to them at all.
 *  2. POST /cards — issues the actual card against that userId, with
 *     a title, color, brand (visa/mastercard), and an initial funding
 *     amount pulled from the given currency wallet.
 *
 * No raw card number/CVV ever passes through this backend in either
 * direction — Eversend generates and holds the card; we only ever
 * reference it by cardId.
 */

// POST /api/v1/cards/kyc-document — Body: { fileBase64, fileName, mimeType }
// Uploads a real government-ID document (photo/scan) to the private
// `kyc-documents` Supabase Storage bucket (see supabase/schema.sql) —
// only used on the real-KYC path, never touched when the user chooses
// "proceed without KYC" instead. Returns { path } to pass into
// POST /cards/user's `documentPath` field.
router.post('/kyc-document', requireAppUser, async (req, res, next) => {
  try {
    const { fileBase64, fileName, mimeType } = req.body || {};
    if (!fileBase64 || !fileName) {
      return res.status(400).json({ error: 'fileBase64 and fileName are required.' });
    }

    const buffer = Buffer.from(fileBase64, 'base64');
    const path = `${req.user.id}/${Date.now()}-${fileName}`;
    const { error } = await supabaseAdmin.storage
      .from('kyc-documents')
      .upload(path, buffer, { contentType: mimeType || 'application/octet-stream', upsert: false });

    if (error) return res.status(500).json({ error: 'Could not upload your ID document. Please try again.' });

    res.json({ path });
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/cards/user
// Real-KYC path — Body: { firstName, lastName, email, phone, country,
//   state, city, address, zipCode, idType, idNumber, documentPath }
//   idType must be one of: National_ID, Passport, Driving_License
//   documentPath comes from POST /kyc-document above.
// No-KYC path — Body: { skipKyc: true, firstName, lastName, email,
//   phone, country, state, city, address, zipCode }
//   idType/idNumber are generated here rather than collected: idType
//   is 'ID' for an African country, 'FOREIGN' otherwise, and idNumber
//   is a generated unique cardholder reference — both are recorded in
//   card_kyc_identities and sent to Eversend the same way real values
//   would be. NOTE: 'ID'/'FOREIGN' are NOT documented Eversend idType
//   values (their confirmed enum is National_ID/Passport/Driving_
//   License) — this hasn't been verified against a live call, per
//   Backend/README.md's note on this environment's restricted network
//   egress. If Eversend rejects these, the fix is a one-line mapping
//   here, not a redesign.
router.post('/user', requireAppUser, async (req, res, next) => {
  try {
    const skipKyc = req.body?.skipKyc === true;
    const country = req.body?.country;
    const baseRequired = ['firstName', 'lastName', 'email', 'phone', 'country', 'state', 'city', 'address', 'zipCode'];
    const missingBase = baseRequired.filter((f) => !req.body?.[f]);
    if (missingBase.length) {
      return res.status(400).json({ error: `Missing required field(s): ${missingBase.join(', ')}` });
    }

    let eversendBody;
    let kycRow;

    if (skipKyc) {
      // Per product spec: no documents are asked for. African countries
      // get a National_ID, foreign countries get a Passport. The idNumber
      // is auto-generated and guaranteed not to collide with any existing
      // one in card_kyc_identities (see generateUniqueCardholderId).
      const idType = AFRICAN_COUNTRY_CODES.has(country.toUpperCase())
        ? 'National_ID'
        : 'Passport';
      const idNumber = await generateUniqueCardholderId();
      eversendBody = { ...req.body, idType, idNumber };
      delete eversendBody.skipKyc;
      kycRow = { method: 'generated', country, id_type: idType, id_number: idNumber, document_path: null };
    } else {
      const missing = ['idType', 'idNumber', 'documentPath'].filter((f) => !req.body?.[f]);
      if (missing.length) {
        return res.status(400).json({ error: `Missing required field(s): ${missing.join(', ')}` });
      }
      if (!['National_ID', 'Passport', 'Driving_License'].includes(req.body.idType)) {
        return res.status(400).json({ error: 'idType must be National_ID, Passport, or Driving_License.' });
      }
      eversendBody = { ...req.body };
      delete eversendBody.documentPath;
      kycRow = {
        method: 'document',
        country,
        id_type: req.body.idType,
        id_number: req.body.idNumber,
        document_path: req.body.documentPath,
      };
    }

    const data = await eversend.post('/cards/user', eversendBody);
    // Eversend's own docs confirm the field is "userId" ("the card
    // userId is the key needed when creating a new card") — checked
    // first, with id/data.userId/data.id as defensive fallbacks in
    // case the real response nests differently than the docs' prose
    // implies (no example response body is published to confirm the
    // exact shape/depth).
    const cardUserId =
      data?.userId ?? data?.id ?? data?.data?.userId ?? data?.data?.id;

    if (!cardUserId) {
      // Never report success without a usable ID — this used to
      // silently respond 200 with `cardUserId: undefined` written to
      // both tables, which meant _issueCard() on the next screen
      // always failed later with a confusing "identity profile
      // wasn't saved correctly" message that pointed the user at the
      // wrong step. Fail here, at the point that's actually broken,
      // with the real Eversend response attached so the cause is
      // visible immediately instead of one screen later.
      return res.status(502).json({
        error: "Creating your cardholder profile didn't complete. Please try again, or contact support if this keeps happening.",
        raw: data,
      });
    }

    await supabaseAdmin
      .from('profiles')
      .update({ eversend_card_user_id: cardUserId })
      .eq('id', req.user.id);

    await supabaseAdmin.from('card_kyc_identities').insert({
      user_id: req.user.id,
      eversend_card_user_id: cardUserId,
      ...kycRow,
    });

    res.json({ ...data, userId: cardUserId, id: cardUserId });
  } catch (err) {
    next(err);
  }
});

router.patch('/user', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.patch('/cards/user', req.body);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.get('/user', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.get('/cards/user');
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/cards
// Body: { title, color, amount, userId, currency, brand,
//         cardFeeType: 'one_time' | 'monthly', skipKyc? }
// color: blue | black | purple | orange | yellow
// brand: visa | mastercard
// userId: the id returned from POST /cards/user above
//
// Dutch Remit's own card-creation fee — separate from, and on top of,
// the initial funding `amount` above: $3.50 once (cardFeeType:
// 'one_time', maps to Eversend's isNonSubscription: true) or
// $1.10/month (cardFeeType: 'monthly', isNonSubscription: false).
// `skipKyc` (echoing what was sent to POST /cards/user) adds a
// further $1.50. Recorded as its own 'card_creation_fee' transaction,
// separate from the 'card_fund' one, so the two never get confused in
// the transaction history.
router.post('/', requireAppUser, async (req, res, next) => {
  try {
    const { title, amount, userId, currency, brand, cardFeeType = 'monthly', skipKyc } = req.body || {};
    if (!title || !amount || !userId || !currency || !brand) {
      return res.status(400).json({
        error: 'title, amount, userId, currency and brand are required.',
      });
    }
    if (!['visa', 'mastercard'].includes(brand)) {
      return res.status(400).json({ error: 'brand must be visa or mastercard.' });
    }
    if (!['one_time', 'monthly'].includes(cardFeeType)) {
      return res.status(400).json({ error: "cardFeeType must be 'one_time' or 'monthly'." });
    }

    const isNonSubscription = cardFeeType === 'one_time';
    const cardCreationFee = isNonSubscription ? CARD_FEE_ONE_TIME : CARD_FEE_MONTHLY;
    const kycSkipFee = skipKyc ? KYC_SKIP_FEE : 0;
    const totalFee = +(cardCreationFee + kycSkipFee).toFixed(2);

    // Real balance check: the user is about to be charged the card's
    // initial funding amount plus Dutch Remit's own creation fee —
    // both are a real debit against their tracked balance, and this
    // route previously had no check on either. Cards are always
    // issued in USD (confirmed against Eversend's own docs), so
    // `amount` here is already the right unit to check directly.
    if (Number(amount) < MIN_DEPOSIT_USD || Number(amount) > MAX_DEPOSIT_USD) {
      return res.status(400).json({ error: `Card funding amount must be between \$${MIN_DEPOSIT_USD} and \$${MAX_DEPOSIT_USD}.` });
    }
    const totalChargeUsd = +(Number(amount) + totalFee).toFixed(2);
    const debitResult = await debitIfSufficient(req.user.id, totalChargeUsd, 'card creation + funding');
    if (!debitResult.ok) {
      return res.status(402).json({
        error: `Your balance (\$${debitResult.currentBalance.toFixed(2)}) doesn't cover this card's funding amount plus fees (\$${totalChargeUsd.toFixed(2)}). Add funds and try again.`,
        currentBalance: debitResult.currentBalance,
      });
    }

    const data = await eversend.post('/cards', {
      title,
      color: req.body.color || 'blue',
      amount,
      userId,
      currency,
      brand,
      isNonSubscription,
    });

    // Same silent-failure risk as POST /cards/user: if Eversend's
    // real response doesn't nest the id the way this expects, a
    // broken row (eversend_card_id: null) used to get inserted
    // anyway and the endpoint still reported 200 — the card looked
    // "created" in the app, but every later fund/withdraw/view call
    // hit requireOwnedCard's lookup by eversend_card_id, found
    // nothing, and failed with "card not found" one screen later.
    // Fail here instead, where the real problem is.
    const eversendCardId = data?.id ?? data?.data?.id ?? data?.cardId ?? data?.data?.cardId;
    if (!eversendCardId) {
      return res.status(502).json({
        error: "Creating your card didn't complete. Please try again, or contact support if this keeps happening.",
        raw: data,
      });
    }

    await supabaseAdmin.from('cards').insert({
      user_id: req.user.id,
      eversend_card_id: eversendCardId,
      title,
      color: req.body.color || 'blue',
      kind: 'virtual',
      status: 'active',
      raw_response: data,
    });

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'card_fund',
      status: data?.status ?? 'completed',
      amount,
      currency,
      method: 'card',
      provider: 'eversend',
      raw_response: data,
    });

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'card_creation_fee',
      status: 'completed',
      amount: totalFee,
      currency: 'USD',
      method: 'card',
      provider: 'dutch_remit',
      raw_response: { cardFeeType, skipKyc: !!skipKyc, cardCreationFee, kycSkipFee },
    });

    res.json({ ...data, id: eversendCardId, cardId: eversendCardId, feeCharged: { cardCreationFee, kycSkipFee, totalFee } });
  } catch (err) {
    next(err);
  }
});

router.get('/', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.get('/cards');
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/cards/instant
// Body: { title?, amount, currency, brand, color? }
// The $5 "instant card" tier: NO KYC, NO documents, issued immediately.
//
// Flow (all automated, nothing asked of the user):
//   1. Ensure a usable Eversend cardholder exists for this Dutch Remit
//      user. If the user already has one (profiles.eversend_card_user_id),
//      reuse it. Otherwise auto-provision one behind the scenes by
//      populating every required cardholder field with synthetic-but-
//      valid values (name/email/phone from the user's profile where
//      available, address fields filled with sane defaults), using the
//      same National_ID/Passport + collision-proof idNumber scheme as
//      the no-KYC path. This is the "backup: automatically creates a
//      cardholder by populating all the fields" behaviour.
//   2. Immediately issue the card against that cardholder.
//   3. Charge the flat $5 instant fee (instead of the normal creation +
//      KYC-skip fees).
router.post('/instant', requireAppUser, async (req, res, next) => {
  try {
    const { amount, currency, brand } = req.body || {};
    if (!amount || !currency || !brand) {
      return res.status(400).json({ error: 'amount, currency and brand are required.' });
    }
    if (!['visa', 'mastercard'].includes(brand)) {
      return res.status(400).json({ error: 'brand must be visa or mastercard.' });
    }

    // --- Step 1: resolve or auto-provision a cardholder ---
    const { data: profile } = await supabaseAdmin
      .from('profiles')
      .select('eversend_card_user_id, first_name, last_name, email, phone_number, country')
      .eq('id', req.user.id)
      .maybeSingle();

    let cardUserId = profile?.eversend_card_user_id || null;

    if (!cardUserId) {
      // No cardholder yet — build one automatically with all fields
      // populated. Missing profile values fall back to safe defaults so
      // Eversend's required-field validation always passes.
      const country = (profile?.country || 'CM').toUpperCase();
      const idType = AFRICAN_COUNTRY_CODES.has(country) ? 'National_ID' : 'Passport';
      const idNumber = await generateUniqueCardholderId();
      const firstName = profile?.first_name || 'Dutch';
      const lastName = profile?.last_name || 'Remit';
      const email = profile?.email || `user-${req.user.id}@dutchremit.dubiabank.com`;
      const phone = profile?.phone_number || '+237600000000';

      const cardholderBody = {
        firstName,
        lastName,
        email,
        phone,
        country,
        state: 'N/A',
        city: 'N/A',
        address: 'N/A',
        zipCode: '00000',
        idType,
        idNumber,
      };

      const created = await eversend.post('/cards/user', cardholderBody);
      cardUserId = created?.id ?? created?.data?.id ?? created?.userId;

      await supabaseAdmin
        .from('profiles')
        .update({ eversend_card_user_id: cardUserId })
        .eq('id', req.user.id);

      await supabaseAdmin.from('card_kyc_identities').insert({
        user_id: req.user.id,
        eversend_card_user_id: cardUserId,
        method: 'instant_auto',
        country,
        id_type: idType,
        id_number: idNumber,
        document_path: null,
      });
    }

    if (!cardUserId) {
      return res.status(502).json({ error: 'Could not provision a cardholder for instant issuance.' });
    }

    // --- Step 2: issue the card immediately ---
    const title = req.body.title || `${req.body.color || 'blue'} card`;
    const color = req.body.color || 'blue';

    // Real balance check — same reasoning as the standard card
    // creation route above: the instant tier's flat fee plus the
    // funding amount is a real debit, previously unchecked.
    const totalChargeUsd = +(Number(amount) + INSTANT_CARD_FEE).toFixed(2);
    const debitResult = await debitIfSufficient(req.user.id, totalChargeUsd, 'instant card creation + funding');
    if (!debitResult.ok) {
      return res.status(402).json({
        error: `Your balance (\$${debitResult.currentBalance.toFixed(2)}) doesn't cover this card's funding amount plus the \$${INSTANT_CARD_FEE.toFixed(2)} instant fee. Add funds and try again.`,
        currentBalance: debitResult.currentBalance,
      });
    }

    const data = await eversend.post('/cards', {
      title,
      color,
      amount,
      userId: cardUserId,
      currency,
      brand,
      isNonSubscription: true,
    });

    // Same fail-loud fix as POST / above — never insert a card row
    // with no real Eversend ID behind it.
    const eversendCardId = data?.id ?? data?.data?.id ?? data?.cardId ?? data?.data?.cardId;
    if (!eversendCardId) {
      return res.status(502).json({
        error: "Creating your card didn't complete. Please try again, or contact support if this keeps happening.",
        raw: data,
      });
    }

    await supabaseAdmin.from('cards').insert({
      user_id: req.user.id,
      eversend_card_id: eversendCardId,
      title,
      color,
      kind: 'virtual',
      status: 'active',
      raw_response: data,
    });

    // Card funding transaction
    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'card_fund',
      status: data?.status ?? 'completed',
      amount,
      currency,
      method: 'card',
      provider: 'eversend',
      raw_response: data,
    });

    // --- Step 3: flat instant fee (replaces creation + KYC-skip fees) ---
    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'card_creation_fee',
      status: 'completed',
      amount: INSTANT_CARD_FEE,
      currency: 'USD',
      method: 'card',
      provider: 'dutch_remit',
      raw_response: { tier: 'instant', instantCardFee: INSTANT_CARD_FEE },
    });

    res.json({ ...data, id: eversendCardId, cardId: eversendCardId, feeCharged: { instantCardFee: INSTANT_CARD_FEE, totalFee: INSTANT_CARD_FEE } });
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/cards/mine — issued + linked cards together, for the
// card-to-card transfer picker (card_to_card_transfer_screen.dart).
// Never returns a full card number for either kind. Registered before
// GET /:cardId below so "mine" isn't swallowed as a :cardId value.
router.get('/mine', requireAppUser, async (req, res, next) => {
  try {
    const [issued, linked] = await Promise.all([
      supabaseAdmin.from('cards').select('*').eq('user_id', req.user.id).eq('status', 'active'),
      supabaseAdmin.from('linked_cards').select('*').eq('user_id', req.user.id).eq('status', 'active'),
    ]);

    if (issued.error || linked.error) return res.status(500).json({ error: 'Could not load your cards.' });

    const cards = [
      ...(issued.data || []).map((c) => ({
        id: c.id,
        source: 'issued',
        title: c.title,
        color: c.color,
        label: c.title || 'Dutch Remit card',
      })),
      ...(linked.data || []).map((c) => ({
        id: c.id,
        source: 'linked',
        title: c.masked_card_number,
        brand: c.card_brand,
        label: `${c.card_brand || 'Card'} ${c.masked_card_number}`,
      })),
    ];

    res.json({ cards });
  } catch (err) {
    next(err);
  }
});

router.get('/:cardId', requireAppUser, async (req, res, next) => {
  try {
    const card = await requireOwnedCard(req, res, req.params.cardId);
    if (!card) return;
    const data = await eversend.get(`/cards/${req.params.cardId}`);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.get('/:cardId/transactions', requireAppUser, async (req, res, next) => {
  try {
    const card = await requireOwnedCard(req, res, req.params.cardId);
    if (!card) return;
    const data = await eversend.get(`/cards/${req.params.cardId}/transactions`);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.get('/transactions/all', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.get('/cards/transactions');
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/cards/fund — Body: { cardId, amount, currency }
router.post('/fund', requireAppUser, async (req, res, next) => {
  try {
    const { cardId, amount, currency, amountUsd } = req.body || {};
    if (!cardId || !amount || !currency) {
      return res.status(400).json({ error: 'cardId, amount and currency are required.' });
    }
    const card = await requireOwnedCard(req, res, cardId);
    if (!card) return;

    // Real balance check before funding a card — a card top-up is a
    // real debit from the user's tracked wallet balance, and
    // previously had no check against it at all. When funding from a
    // non-USD wallet (e.g. XAF), the caller is expected to supply
    // amountUsd using the rate already shown on the fund screen;
    // falling back to the raw `amount` is only correct when currency
    // is genuinely USD.
    const chargeAmountUsd = Number(amountUsd ?? (currency === 'USD' ? amount : null));
    if (!(chargeAmountUsd > 0)) {
      return res.status(400).json({ error: 'A valid amountUsd is required to check your balance for this currency.' });
    }
    if (chargeAmountUsd < MIN_DEPOSIT_USD || chargeAmountUsd > MAX_DEPOSIT_USD) {
      return res.status(400).json({ error: `Card top-up amount must be between \$${MIN_DEPOSIT_USD} and \$${MAX_DEPOSIT_USD}.` });
    }
    const debitResult = await debitIfSufficient(req.user.id, chargeAmountUsd, `card fund (${cardId})`);
    if (!debitResult.ok) {
      return res.status(402).json({
        error: `Your balance (\$${debitResult.currentBalance.toFixed(2)}) doesn't cover this top-up. Add funds and try again.`,
        currentBalance: debitResult.currentBalance,
      });
    }

    const data = await eversend.post('/cards/fund', { cardId, amount, currency });

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'card_fund',
      status: data?.status ?? 'pending',
      amount,
      currency,
      card_id: cardId,
      provider: 'eversend',
      raw_response: data,
    });

    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/cards/withdraw — Body: { cardId, amount, currency }
router.post('/withdraw', requireAppUser, async (req, res, next) => {
  try {
    const { cardId, amount, currency, amountUsd } = req.body || {};
    if (!cardId || !amount || !currency) {
      return res.status(400).json({ error: 'cardId, amount and currency are required.' });
    }
    const card = await requireOwnedCard(req, res, cardId);
    if (!card) return;
    const data = await eversend.post('/cards/withdraw', { cardId, amount, currency });

    // Credit the withdrawn amount back to the user's tracked
    // balance — the card's money is genuinely returning to their
    // wallet, so their real balance needs to reflect that the same
    // way a deposit does. Best-effort: if this fails, the card
    // withdrawal itself has already completed on Eversend's side, so
    // the transaction is still recorded and reported as successful;
    // a missed ledger credit here needs a manual reconciliation
    // rather than pretending the whole withdrawal failed.
    try {
      const creditAmountUsd = Number(amountUsd ?? (currency === 'USD' ? amount : null));
      if (creditAmountUsd > 0) {
        await credit(req.user.id, creditAmountUsd, `card withdraw (${cardId})`);
      }
    } catch (_) {}

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'card_withdraw',
      status: data?.status ?? 'pending',
      amount,
      currency,
      card_id: cardId,
      provider: 'eversend',
      raw_response: data,
    });

    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.post('/:cardId/freeze', requireAppUser, async (req, res, next) => {
  try {
    const card = await requireOwnedCard(req, res, req.params.cardId);
    if (!card) return;
    const data = await eversend.post(`/cards/${req.params.cardId}/freeze`, {});
    await supabaseAdmin.from('cards').update({ status: 'frozen' }).eq('eversend_card_id', req.params.cardId);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.post('/:cardId/unfreeze', requireAppUser, async (req, res, next) => {
  try {
    const card = await requireOwnedCard(req, res, req.params.cardId);
    if (!card) return;
    const data = await eversend.post(`/cards/${req.params.cardId}/unfreeze`, {});
    await supabaseAdmin.from('cards').update({ status: 'active' }).eq('eversend_card_id', req.params.cardId);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.post('/:cardId/terminate', requireAppUser, async (req, res, next) => {
  try {
    const card = await requireOwnedCard(req, res, req.params.cardId);
    if (!card) return;
    const data = await eversend.post(`/cards/${req.params.cardId}/terminate`, {});
    await supabaseAdmin.from('cards').update({ status: 'terminated' }).eq('eversend_card_id', req.params.cardId);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// --- Card linking ("Add a Card") — a different feature from card
// issuance above: attaching a card the user already owns elsewhere as
// a funding source, rather than Dutch Remit issuing them a new one.
//
// Flow, exactly as specified: (1) the user must already hold at least
// one Dutch-Remit-issued card, (2) they confirm their name/email/
// phone/address, (3) they pay a flat $2.10 retrieval fee, (4) they
// enter the card to link, which is then "retrieved and linked".
//
// SECURITY: the CVV is read from the request body and used only to
// satisfy that read — it is never written to a variable that outlives
// this handler, never logged, and never inserted into any table (see
// linked_cards' schema comment). The card number is stored masked
// (last 4 digits) only. This is still not a PCI-DSS-compliant card
// vault — a real one tokenizes the card client-side (hosted field/
// iframe/SDK) so this backend never receives the raw number at all.
// Treat this as a prototype-grade implementation of the flow you
// asked for, not a production card-data pipeline.

function maskCardNumber(rawNumber) {
  const digits = rawNumber.replace(/\D/g, '');
  const last4 = digits.slice(-4);
  return `•••• •••• •••• ${last4}`;
}

function guessCardBrand(rawNumber) {
  const digits = rawNumber.replace(/\D/g, '');
  if (digits.startsWith('4')) return 'visa';
  if (/^(5[1-5]|2[2-7])/.test(digits)) return 'mastercard';
  return 'card';
}

// POST /api/v1/cards/link
// Body: { firstName, lastName, email, phone, address, cardNumber,
//         expiryMonth, expiryYear, cvv, cardholderName }
router.post('/link', requireAppUser, async (req, res, next) => {
  try {
    const { count, error: countError } = await supabaseAdmin
      .from('cards')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', req.user.id)
      .eq('status', 'active');

    if (countError) return res.status(500).json({ error: 'Could not verify your existing cards.' });
    if (!count) {
      return res.status(400).json({
        error: 'You need to create a Dutch Remit card first before you can link another card.',
      });
    }

    const identityFields = ['firstName', 'lastName', 'email', 'phone', 'address'];
    const missingIdentity = identityFields.filter((f) => !req.body?.[f]);
    if (missingIdentity.length) {
      return res.status(400).json({ error: `Missing required field(s): ${missingIdentity.join(', ')}` });
    }

    const { cardNumber, expiryMonth, expiryYear, cvv, cardholderName } = req.body || {};
    if (!cardNumber || !expiryMonth || !expiryYear || !cvv) {
      return res.status(400).json({ error: 'cardNumber, expiryMonth, expiryYear and cvv are required.' });
    }
    const digits = cardNumber.replace(/\D/g, '');
    if (digits.length < 12 || digits.length > 19) {
      return res.status(400).json({ error: 'Enter a valid card number.' });
    }
    if (!/^\d{3,4}$/.test(cvv)) {
      return res.status(400).json({ error: 'Enter a valid CVV.' });
    }
    // cvv is intentionally never referenced again past this point.

    const { data: linkedCard, error: linkError } = await supabaseAdmin
      .from('linked_cards')
      .insert({
        user_id: req.user.id,
        masked_card_number: maskCardNumber(cardNumber),
        card_brand: guessCardBrand(cardNumber),
        expiry_month: expiryMonth,
        expiry_year: expiryYear,
        cardholder_name: cardholderName || `${req.body.firstName} ${req.body.lastName}`,
        status: 'active',
      })
      .select()
      .single();

    if (linkError) return res.status(500).json({ error: 'Could not link your card.' });

    // Real balance check for the card-link/retrieval fee — this used
    // to insert a transaction row for CARD_LINK_FEE with no check at
    // all against the user's actual balance.
    const debitResult = await debitIfSufficient(req.user.id, CARD_LINK_FEE, 'card link/retrieval fee');
    if (!debitResult.ok) {
      // The card row above is already inserted at this point — rather
      // than try to unwind that insert (risking a partial, confusing
      // state), remove it and report the failure cleanly so the user
      // isn't left with a "linked" card they were never actually
      // charged for.
      await supabaseAdmin.from('linked_cards').delete().eq('id', linkedCard.id);
      return res.status(402).json({
        error: `Your balance (\$${debitResult.currentBalance.toFixed(2)}) doesn't cover the \$${CARD_LINK_FEE.toFixed(2)} link fee. Add funds and try again.`,
        currentBalance: debitResult.currentBalance,
      });
    }

    await supabaseAdmin.from('transactions').insert({
      user_id: req.user.id,
      type: 'card_link_fee',
      status: 'completed',
      amount: CARD_LINK_FEE,
      currency: 'USD',
      method: 'card',
      provider: 'dutch_remit',
      raw_response: { note: 'Card retrieval/link fee' },
    });

    res.json({ linkedCard, feeCharged: CARD_LINK_FEE });
  } catch (err) {
    next(err);
  }
});

// --- Card-to-card transfers — the ledger for moving money between
// two of the caller's own cards, or from the caller's card to another
// Dutch Remit user's card. Neither Eversend nor Klasha expose a real
// card-to-card transfer rail, so this is an internal ledger entry
// (same model as the existing "send to another Dutch Remit user"
// wallet-balance transfer) — see card_transfers' schema comment.

// POST /api/v1/cards/transfer
// Own cards: { fromCardId, fromCardSource, toCardId, toCardSource, amount, currency?, note? }
// To another user: { fromCardId, fromCardSource, toUserId, amount, currency?, note? } —
//   toCardId/toCardSource are optional here: if omitted, the
//   recipient's most-recently-created active card is used
//   automatically (the sender only needs to know *who*, not which of
//   the recipient's cards to hit).
router.post('/transfer', requireAppUser, async (req, res, next) => {
  try {
    const {
      fromCardId,
      fromCardSource,
      toUserId,
      amount,
      currency = 'USD',
      note,
    } = req.body || {};
    let { toCardId, toCardSource } = req.body || {};

    if (!fromCardId || !fromCardSource || !amount) {
      return res.status(400).json({ error: 'fromCardId, fromCardSource and amount are required.' });
    }
    if (!toCardId && !toUserId) {
      return res.status(400).json({ error: 'Provide either toCardId (your own card) or toUserId (another user).' });
    }
    if (!['issued', 'linked'].includes(fromCardSource)) {
      return res.status(400).json({ error: "fromCardSource must be 'issued' or 'linked'." });
    }
    if (Number(amount) <= 0) {
      return res.status(400).json({ error: 'amount must be greater than 0.' });
    }

    const fromTable = fromCardSource === 'issued' ? 'cards' : 'linked_cards';
    const { data: fromCard, error: fromError } = await supabaseAdmin
      .from(fromTable)
      .select('id')
      .eq('id', fromCardId)
      .eq('user_id', req.user.id)
      .maybeSingle();
    if (fromError || !fromCard) {
      return res.status(400).json({ error: "That source card doesn't belong to you." });
    }

    const isOwnTransfer = !toUserId || toUserId === req.user.id;
    const destinationUserId = isOwnTransfer ? req.user.id : toUserId;

    if (!toCardId) {
      // No specific destination card given for a to-another-user
      // transfer — resolve their most recently created active card,
      // preferring an issued Dutch Remit card over a linked one.
      const [issued, linked] = await Promise.all([
        supabaseAdmin
          .from('cards')
          .select('id')
          .eq('user_id', destinationUserId)
          .eq('status', 'active')
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle(),
        supabaseAdmin
          .from('linked_cards')
          .select('id')
          .eq('user_id', destinationUserId)
          .eq('status', 'active')
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle(),
      ]);
      if (issued.data) {
        toCardId = issued.data.id;
        toCardSource = 'issued';
      } else if (linked.data) {
        toCardId = linked.data.id;
        toCardSource = 'linked';
      } else {
        return res.status(400).json({ error: "That user doesn't have a card to receive this transfer yet." });
      }
    }

    if (!['issued', 'linked'].includes(toCardSource)) {
      return res.status(400).json({ error: "toCardSource must be 'issued' or 'linked'." });
    }
    if (fromCardId === toCardId) {
      return res.status(400).json({ error: 'Choose two different cards to transfer between.' });
    }

    const toTable = toCardSource === 'issued' ? 'cards' : 'linked_cards';
    const { data: toCard, error: toError } = await supabaseAdmin
      .from(toTable)
      .select('id, user_id')
      .eq('id', toCardId)
      .eq('user_id', destinationUserId)
      .maybeSingle();
    if (toError || !toCard) {
      return res.status(400).json({ error: "That destination card couldn't be found." });
    }

    // Real fund-safety check — this route previously recorded a
    // card_transfers row and two transactions rows with NO check on
    // whether the sender's tracked balance actually covered the
    // amount, and no ledger entry at all. A user could transfer to
    // another user's card an unlimited number of times with nothing
    // backing it. Fixed: debit the sender first (refusing if
    // insufficient), and for a transfer to a different user, credit
    // them the same amount — same-user own-card transfers don't need
    // a credit since the money conceptually stays with the same
    // person, just moves between two of their cards.
    const chargeAmountUsd = Number(req.body.amountUsd ?? (currency === 'USD' ? amount : null));
    if (!(chargeAmountUsd > 0)) {
      return res.status(400).json({ error: 'A valid amountUsd is required to check your balance for this currency.' });
    }
    const debitResult = await debitIfSufficient(req.user.id, chargeAmountUsd, `card transfer to ${isOwnTransfer ? 'own card' : 'another user'}`);
    if (!debitResult.ok) {
      return res.status(402).json({
        error: `Your balance (\$${debitResult.currentBalance.toFixed(2)}) doesn't cover this transfer. Add funds and try again.`,
        currentBalance: debitResult.currentBalance,
      });
    }
    if (!isOwnTransfer) {
      // If crediting the recipient fails after the sender's balance
      // was already debited, refund the sender immediately rather
      // than leave the money in limbo — the transfer as a whole must
      // not proceed if both legs can't complete.
      try {
        await credit(toUserId, chargeAmountUsd, `card transfer received from ${req.user.id}`);
      } catch (creditErr) {
        await credit(req.user.id, chargeAmountUsd, 'card transfer refund (recipient credit failed)');
        return res.status(500).json({ error: 'Could not complete the transfer. Your balance has not been charged.' });
      }
    }

    const reference = `DR-CT-${Date.now()}`;
    const { data: transfer, error: transferError } = await supabaseAdmin
      .from('card_transfers')
      .insert({
        from_user_id: req.user.id,
        to_user_id: isOwnTransfer ? req.user.id : toUserId,
        from_card_id: fromCardId,
        from_card_source: fromCardSource,
        to_card_id: toCardId,
        to_card_source: toCardSource,
        amount,
        currency,
        status: 'completed',
        reference,
        note: note || null,
      })
      .select()
      .single();

    if (transferError) return res.status(500).json({ error: 'Could not record the transfer.' });

    const transactionRows = [
      {
        user_id: req.user.id,
        type: 'card_transfer',
        status: 'completed',
        amount,
        currency,
        method: 'card',
        provider: 'dutch_remit',
        card_id: fromCardId,
        raw_response: { direction: 'debit', reference, toCardId, toCardSource },
      },
    ];
    if (!isOwnTransfer) {
      transactionRows.push({
        user_id: toUserId,
        type: 'card_transfer',
        status: 'completed',
        amount,
        currency,
        method: 'card',
        provider: 'dutch_remit',
        card_id: toCardId,
        raw_response: { direction: 'credit', reference, fromCardId, fromCardSource },
      });
    }
    await supabaseAdmin.from('transactions').insert(transactionRows);

    res.json({ transfer });
  } catch (err) {
    next(err);
  }
});

module.exports = router;

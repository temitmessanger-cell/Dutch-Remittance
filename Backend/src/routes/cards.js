const express = require('express');
const crypto = require('crypto');
const { eversend } = require('../eversendClient');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');

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

// Linking an existing card (as opposed to issuing a new Dutch-Remit
// card) charges a flat $2.10 retrieval fee — see POST /link below.
const CARD_LINK_FEE = 2.1;

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
      const idType = AFRICAN_COUNTRY_CODES.has(country.toUpperCase()) ? 'ID' : 'FOREIGN';
      const idNumber = `DR-${crypto.randomUUID()}`;
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
    const cardUserId = data?.id ?? data?.data?.id ?? data?.userId;

    await supabaseAdmin
      .from('profiles')
      .update({ eversend_card_user_id: cardUserId })
      .eq('id', req.user.id);

    await supabaseAdmin.from('card_kyc_identities').insert({
      user_id: req.user.id,
      eversend_card_user_id: cardUserId,
      ...kycRow,
    });

    res.json(data);
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

    const data = await eversend.post('/cards', {
      title,
      color: req.body.color || 'blue',
      amount,
      userId,
      currency,
      brand,
      isNonSubscription,
    });

    await supabaseAdmin.from('cards').insert({
      user_id: req.user.id,
      eversend_card_id: data?.id ?? data?.data?.id ?? null,
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

    res.json({ ...data, feeCharged: { cardCreationFee, kycSkipFee, totalFee } });
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
    const data = await eversend.get(`/cards/${req.params.cardId}`);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.get('/:cardId/transactions', requireAppUser, async (req, res, next) => {
  try {
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
    const { cardId, amount, currency } = req.body || {};
    if (!cardId || !amount || !currency) {
      return res.status(400).json({ error: 'cardId, amount and currency are required.' });
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
    const { cardId, amount, currency } = req.body || {};
    if (!cardId || !amount || !currency) {
      return res.status(400).json({ error: 'cardId, amount and currency are required.' });
    }
    const data = await eversend.post('/cards/withdraw', { cardId, amount, currency });

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
    const data = await eversend.post(`/cards/${req.params.cardId}/freeze`, {});
    await supabaseAdmin.from('cards').update({ status: 'frozen' }).eq('eversend_card_id', req.params.cardId);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.post('/:cardId/unfreeze', requireAppUser, async (req, res, next) => {
  try {
    const data = await eversend.post(`/cards/${req.params.cardId}/unfreeze`, {});
    await supabaseAdmin.from('cards').update({ status: 'active' }).eq('eversend_card_id', req.params.cardId);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

router.post('/:cardId/terminate', requireAppUser, async (req, res, next) => {
  try {
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

const express = require('express');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');

const router = express.Router();

// GET /api/v1/users/search?q=<term> — real cross-platform user search
// (not the caller's own saved contacts/beneficiaries — see
// beneficiaries.js and contacts.js for that). Powers the Send/Request
// flow's recipient picker so a user can find and pay any other real
// Dutch Remit user by name or username, not only people they've
// already saved. Only returns safe, public-facing fields — never
// email or phone to a stranger, matching the same privacy posture as
// the businesses directory.
router.get('/search', requireAppUser, async (req, res, next) => {
  try {
    const term = (req.query.q || '').toString().trim();
    if (term.length < 2) {
      return res.json({ users: [] });
    }

    const { data, error } = await supabaseAdmin
      .from('profiles')
      .select('id, username, first_name, last_name, avatar_url')
      .neq('id', req.user.id)
      .or(`username.ilike.%${term}%,first_name.ilike.%${term}%,last_name.ilike.%${term}%`)
      .limit(20);

    if (error) return res.status(500).json({ error: 'Could not search users.' });

    const users = (data || []).map((u) => ({
      id: u.id,
      username: u.username,
      name: `${u.first_name || ''} ${u.last_name || ''}`.trim() || u.username || 'Dutch Remit user',
      avatar: u.avatar_url,
    }));

    res.json({ users });
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/users/verify — Body: { email?, dutchRemitId? } (exactly
// one required). Used when adding a recipient: name and phone number
// are collected on the client, but the account itself must be
// verified to exist by email or Dutch Remit ID before the contact is
// saved — declines (404) rather than silently saving an unverifiable
// contact.
router.post('/verify', requireAppUser, async (req, res, next) => {
  try {
    const email = (req.body?.email || '').toString().trim();
    const dutchRemitId = (req.body?.dutchRemitId || '').toString().trim();
    if (!email && !dutchRemitId) {
      return res.status(400).json({ error: 'email or dutchRemitId is required.' });
    }

    let query = supabaseAdmin.from('profiles').select('id, username, first_name, last_name, dutch_remit_id, email');
    query = dutchRemitId ? query.ilike('dutch_remit_id', dutchRemitId) : query.ilike('email', email);

    const { data, error } = await query.maybeSingle();
    if (error) return res.status(500).json({ error: 'Could not verify that user.' });
    if (!data) {
      return res.status(404).json({ error: 'No Dutch Remit user found with that email or Dutch Remit ID.' });
    }

    res.json({
      user: {
        id: data.id,
        dutchRemitId: data.dutch_remit_id,
        name: `${data.first_name || ''} ${data.last_name || ''}`.trim() || data.username || 'Dutch Remit user',
      },
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;

const express = require('express');
const { supabaseAdmin } = require('../supabaseClient');
const { requireAppUser } = require('../middleware/requireAppUser');

const router = express.Router();

// GET /Dutch Remit/v3/all-contacts
// Returns { contacts: [...] } shaped exactly how all_contacts.dart /
// send_and_recipients_screen.dart already parse it — backed by the
// real `beneficiaries` table instead of nothing.
router.get('/', requireAppUser, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('beneficiaries')
    .select('*')
    .eq('user_id', req.user.id)
    .order('created_at', { ascending: false });

  if (error) return res.json({ error: 'Could not load contacts.' });

  const contacts = (data || []).map((b) => ({
    id: b.id,
    name: `${b.first_name} ${b.last_name}`.trim(),
    emailAddress: null,
    phoneNumber: b.phone_number,
    country: b.country,
    isBank: b.is_bank,
    isMomo: b.is_momo,
  }));

  res.json({ contacts });
});

module.exports = router;

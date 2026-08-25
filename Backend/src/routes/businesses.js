const express = require('express');
const { supabaseAdmin } = require('../supabaseClient');

const router = express.Router();

// GET /Dutch Remit/v2/businesses-and-brands
// Returns { businesses: [...] } — see supabase/schema.sql's seed rows.
// No auth required: this is a public directory, same as before.
router.get('/', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('businesses')
    .select('*')
    .eq('is_active', true)
    .order('name');

  if (error) return res.json({ error: 'Could not load businesses.' });

  const businesses = (data || []).map((b) => ({
    id: b.id,
    name: b.name,
    category: b.category,
    logo: b.logo_url,
  }));

  res.json({ businesses });
});

module.exports = router;

const express = require('express');
const { supabaseAdmin } = require('../supabaseClient');
const { requireAppUser } = require('../middleware/requireAppUser');

const router = express.Router();

// GET /api/v1/notifications
router.get('/', requireAppUser, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('notifications')
    .select('*')
    .eq('user_id', req.user.id)
    .order('created_at', { ascending: false })
    .limit(50);

  if (error) return res.status(500).json({ error: 'Could not load notifications.' });
  res.json({ notifications: data || [] });
});

// PATCH /api/v1/notifications/:id — Body: { isRead: true }
router.patch('/:id', requireAppUser, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('notifications')
    .update({ is_read: !!req.body?.isRead })
    .eq('id', req.params.id)
    .eq('user_id', req.user.id)
    .select()
    .single();

  if (error) return res.status(500).json({ error: 'Could not update notification.' });
  res.json({ notification: data });
});

module.exports = router;

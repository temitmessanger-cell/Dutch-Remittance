const express = require('express');
const { supabaseAdmin } = require('../supabaseClient');
const { requireAppUser } = require('../middleware/requireAppUser');

const router = express.Router();

// POST /api/v1/devices
// Body: { deviceId, platform, appVersion }
// Syncs install/device metadata that
// database/hadwin_user_device_info_storage.dart currently only keeps
// on-device. Upserts on deviceId so re-launching doesn't duplicate rows.
router.post('/', requireAppUser, async (req, res, next) => {
  try {
    const { deviceId, platform, appVersion } = req.body || {};
    if (!deviceId) return res.status(400).json({ error: 'deviceId is required.' });

    const { data, error } = await supabaseAdmin
      .from('devices')
      .upsert(
        {
          user_id: req.user.id,
          device_id: deviceId,
          platform,
          app_version: appVersion,
          last_seen_at: new Date().toISOString(),
        },
        { onConflict: 'device_id' }
      )
      .select()
      .single();

    if (error) return res.status(500).json({ error: 'Could not sync device.' });
    res.json({ device: data });
  } catch (err) {
    next(err);
  }
});

module.exports = router;

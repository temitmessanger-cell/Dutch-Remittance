const express = require('express');
const { requireAppUser } = require('../middleware/requireAppUser');
const { supabaseAdmin } = require('../supabaseClient');

const router = express.Router();

// ─────────────────────────────────────────────
// Task definitions — single source of truth
// ─────────────────────────────────────────────
const TASKS = [
  // One-time (follow / subscribe)
  { id: 'youtube_subscribe',  platform: 'YouTube',   action: 'Subscribe',  points: 1, repeatable: false, url: 'https://www.youtube.com/@Dutch.Inc.Platforms?sub_confirmation=1' },
  { id: 'instagram_follow',   platform: 'Instagram', action: 'Follow',     points: 1, repeatable: false, url: 'https://www.instagram.com/dutchincplatforms' },
  { id: 'tiktok_follow',      platform: 'TikTok',    action: 'Follow',     points: 1, repeatable: false, url: 'https://www.tiktok.com/@dutch.inc.platforms' },

  // Daily repeatable — YouTube
  { id: 'youtube_like',       platform: 'YouTube',   action: 'Like',       points: 1, repeatable: true,  url: 'https://www.youtube.com/@Dutch.Inc.Platforms' },
  { id: 'youtube_comment',    platform: 'YouTube',   action: 'Comment',    points: 1, repeatable: true,  url: 'https://www.youtube.com/@Dutch.Inc.Platforms' },
  { id: 'youtube_share',      platform: 'YouTube',   action: 'Share',      points: 1, repeatable: true,  url: 'https://www.youtube.com/@Dutch.Inc.Platforms' },

  // Daily repeatable — Instagram
  { id: 'instagram_like',     platform: 'Instagram', action: 'Like',       points: 1, repeatable: true,  url: 'https://www.instagram.com/dutchincplatforms' },
  { id: 'instagram_comment',  platform: 'Instagram', action: 'Comment',    points: 1, repeatable: true,  url: 'https://www.instagram.com/dutchincplatforms' },
  { id: 'instagram_share',    platform: 'Instagram', action: 'Share',      points: 1, repeatable: true,  url: 'https://www.instagram.com/dutchincplatforms' },

  // Daily repeatable — TikTok
  { id: 'tiktok_like',        platform: 'TikTok',    action: 'Like',       points: 1, repeatable: true,  url: 'https://www.tiktok.com/@dutch.inc.platforms' },
  { id: 'tiktok_comment',     platform: 'TikTok',    action: 'Comment',    points: 1, repeatable: true,  url: 'https://www.tiktok.com/@dutch.inc.platforms' },
  { id: 'tiktok_share',       platform: 'TikTok',    action: 'Share',      points: 1, repeatable: true,  url: 'https://www.tiktok.com/@dutch.inc.platforms' },
];

const REDEEM_POINTS_REQUIRED = 20;

// ─────────────────────────────────────────────
// GET /api/v1/rewards/tasks
// Returns all tasks + completion state for the user
// ─────────────────────────────────────────────
router.get('/tasks', requireAppUser, async (req, res, next) => {
  try {
    const userId = req.user.id;
    const today = new Date().toISOString().slice(0, 10);

    const { data: completions, error } = await supabaseAdmin
      .from('task_completions')
      .select('task_id, completed_at, date_bucket')
      .eq('user_id', userId);

    if (error) throw error;

    const tasksWithStatus = TASKS.map(task => {
      const done = completions.filter(c => c.task_id === task.id);
      let completed = false;
      let earnedToday = false;

      if (!task.repeatable) {
        completed = done.length > 0;
      } else {
        earnedToday = done.some(c => c.date_bucket === today);
        completed = false; // repeatable tasks are never "done" permanently
      }

      return {
        ...task,
        completed,       // one-time: true = done forever
        earnedToday,     // repeatable: true = already earned today
        totalEarned: done.length,
      };
    });

    // Total available points
    const { data: pointsRow } = await supabaseAdmin
      .from('user_points')
      .select('available_points, total_earned, total_redeemed')
      .eq('user_id', userId)
      .maybeSingle();

    res.json({
      tasks: tasksWithStatus,
      points: {
        available: pointsRow?.available_points ?? 0,
        totalEarned: pointsRow?.total_earned ?? 0,
        totalRedeemed: pointsRow?.total_redeemed ?? 0,
        requiredForCard: REDEEM_POINTS_REQUIRED,
      },
    });
  } catch (err) {
    next(err);
  }
});

// ─────────────────────────────────────────────
// POST /api/v1/rewards/complete
// Body: { taskId }
// Awards points for completing a task
// ─────────────────────────────────────────────
router.post('/complete', requireAppUser, async (req, res, next) => {
  try {
    const userId = req.user.id;
    const { taskId } = req.body || {};

    const task = TASKS.find(t => t.id === taskId);
    if (!task) {
      return res.status(400).json({ error: 'Unknown task.' });
    }

    const today = new Date().toISOString().slice(0, 10);

    // Check eligibility
    const { data: existing } = await supabaseAdmin
      .from('task_completions')
      .select('id, date_bucket')
      .eq('user_id', userId)
      .eq('task_id', taskId);

    if (!task.repeatable && existing?.length > 0) {
      return res.status(400).json({ error: 'You\'ve already completed this task.' });
    }
    if (task.repeatable && existing?.some(c => c.date_bucket === today)) {
      return res.status(400).json({ error: 'You\'ve already earned this today. Come back tomorrow!' });
    }

    // Record completion
    const { error: insertErr } = await supabaseAdmin
      .from('task_completions')
      .insert({
        user_id: userId,
        task_id: taskId,
        points_earned: task.points,
        date_bucket: today,
      });

    if (insertErr) throw insertErr;

    // Upsert user_points
    const { data: current } = await supabaseAdmin
      .from('user_points')
      .select('available_points, total_earned, total_redeemed')
      .eq('user_id', userId)
      .maybeSingle();

    const newAvailable = (current?.available_points ?? 0) + task.points;
    const newTotal = (current?.total_earned ?? 0) + task.points;

    const { error: upsertErr } = await supabaseAdmin
      .from('user_points')
      .upsert({
        user_id: userId,
        available_points: newAvailable,
        total_earned: newTotal,
        total_redeemed: current?.total_redeemed ?? 0,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id' });

    if (upsertErr) throw upsertErr;

    res.json({
      success: true,
      pointsEarned: task.points,
      newAvailable,
      message: `+${task.points} point${task.points !== 1 ? 's' : ''} earned!`,
    });
  } catch (err) {
    next(err);
  }
});

// ─────────────────────────────────────────────
// POST /api/v1/rewards/redeem
// Redeem 20pts for a free virtual card + $3 top-up
// ─────────────────────────────────────────────
router.post('/redeem', requireAppUser, async (req, res, next) => {
  try {
    const userId = req.user.id;

    const { data: pointsRow, error: ptErr } = await supabaseAdmin
      .from('user_points')
      .select('available_points, total_earned, total_redeemed')
      .eq('user_id', userId)
      .maybeSingle();

    if (ptErr) throw ptErr;

    const available = pointsRow?.available_points ?? 0;
    if (available < REDEEM_POINTS_REQUIRED) {
      return res.status(400).json({
        error: `You need ${REDEEM_POINTS_REQUIRED} points to redeem. You have ${available}.`,
      });
    }

    // Deduct points
    const { error: deductErr } = await supabaseAdmin
      .from('user_points')
      .update({
        available_points: available - REDEEM_POINTS_REQUIRED,
        total_redeemed: (pointsRow?.total_redeemed ?? 0) + REDEEM_POINTS_REQUIRED,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId);

    if (deductErr) throw deductErr;

    // Log redemption
    const { data: redemption, error: redErr } = await supabaseAdmin
      .from('point_redemptions')
      .insert({
        user_id: userId,
        points_used: REDEEM_POINTS_REQUIRED,
        reward_type: 'free_virtual_card_3usd',
        status: 'pending',
      })
      .select()
      .single();

    if (redErr) throw redErr;

    res.json({
      success: true,
      redemptionId: redemption.id,
      message: 'Redemption submitted! Your free virtual card with $3 will be ready within 24 hours.',
      newAvailable: available - REDEEM_POINTS_REQUIRED,
    });
  } catch (err) {
    next(err);
  }
});

// ─────────────────────────────────────────────
// GET /api/v1/rewards/redemptions
// User's redemption history
// ─────────────────────────────────────────────
router.get('/redemptions', requireAppUser, async (req, res, next) => {
  try {
    const { data, error } = await supabaseAdmin
      .from('point_redemptions')
      .select('*')
      .eq('user_id', req.user.id)
      .order('redeemed_at', { ascending: false });

    if (error) throw error;
    res.json({ redemptions: data });
  } catch (err) {
    next(err);
  }
});

module.exports = router;

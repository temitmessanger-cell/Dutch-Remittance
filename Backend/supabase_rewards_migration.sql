-- ─────────────────────────────────────────────────────────────
-- Dutch Remit — Rewards & Social Tasks migration
-- Run this once in Supabase SQL editor
-- ─────────────────────────────────────────────────────────────

-- 1. Task completions log
CREATE TABLE IF NOT EXISTS task_completions (
  id            UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id       UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  task_id       TEXT        NOT NULL,
  points_earned INTEGER     NOT NULL DEFAULT 1,
  completed_at  TIMESTAMPTZ DEFAULT NOW(),
  date_bucket   DATE        DEFAULT CURRENT_DATE  -- for daily rate limiting
);

CREATE INDEX IF NOT EXISTS idx_task_completions_user  ON task_completions(user_id);
CREATE INDEX IF NOT EXISTS idx_task_completions_daily ON task_completions(user_id, task_id, date_bucket);

-- 2. Running points balance per user
CREATE TABLE IF NOT EXISTS user_points (
  user_id         UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  available_points INTEGER    NOT NULL DEFAULT 0,
  total_earned    INTEGER     NOT NULL DEFAULT 0,
  total_redeemed  INTEGER     NOT NULL DEFAULT 0,
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Redemption history
CREATE TABLE IF NOT EXISTS point_redemptions (
  id           UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  points_used  INTEGER     NOT NULL DEFAULT 20,
  reward_type  TEXT        NOT NULL DEFAULT 'free_virtual_card_3usd',
  status       TEXT        NOT NULL DEFAULT 'pending', -- pending | completed | failed
  card_id      TEXT,        -- filled once the card is issued
  redeemed_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_redemptions_user ON point_redemptions(user_id);

-- 4. RLS — users can only read their own rows
ALTER TABLE task_completions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_points       ENABLE ROW LEVEL SECURITY;
ALTER TABLE point_redemptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user own completions"  ON task_completions  FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "user own points"       ON user_points       FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "user own redemptions"  ON point_redemptions FOR ALL USING (auth.uid() = user_id);

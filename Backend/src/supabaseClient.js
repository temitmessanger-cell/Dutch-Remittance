const { createClient } = require('@supabase/supabase-js');

// Server-side admin client using the service_role key — bypasses Row
// Level Security. Used for everything except password verification.
const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { autoRefreshToken: false, persistSession: false } }
);

// A second client using the anon key, used specifically for
// `auth.signInWithPassword` / `auth.admin.createUser` flows in
// src/routes/auth.js — this is the real Supabase Auth identity store
// (auth.users + GoTrue), now that the old custom backend is gone.
// Every new signup/login gets a genuine Supabase session token back,
// which requireAppUser.js already knows how to verify properly.
const supabaseAuth = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_ANON_KEY,
  { auth: { autoRefreshToken: false, persistSession: false } }
);

module.exports = { supabaseAdmin, supabaseAuth };

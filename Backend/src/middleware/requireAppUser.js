const crypto = require('crypto');
const { supabaseAdmin } = require('../supabaseClient');

/**
 * Resolves whoever is calling into a stable `public.profiles.id`,
 * whichever of two session shapes they present:
 *
 *  1. A real Supabase Auth access token (once the app migrates to
 *     Supabase Auth) — verified properly via supabase.auth.getUser().
 *  2. The Flutter app's *current* custom `authorization_token` (see
 *     lib/components/login_screen/form_component.dart's
 *     `dataReceived['authorization_token']`) — accepted today so the
 *     backend is usable immediately, without forcing an auth
 *     migration before this project can go live. The raw token is
 *     never stored: only its SHA-256 hash, mapped to a profile in
 *     `legacy_sessions` (see supabase/schema.sql), created on first
 *     use and reused after that.
 *
 * Either way, route handlers just read `req.user.id`.
 */
async function requireAppUser(req, res, next) {
  const authHeader = req.headers.authorization || '';
  // The Flutter app's existing getData/sendData helpers
  // (lib/utilities/make_api_request.dart) send the raw token as
  // `Authorization: <token>`, with no `Bearer ` prefix — accept both
  // forms so this works with the app's current calls unchanged as
  // well as any future client that does send the prefix.
  const token = authHeader.startsWith('Bearer ')
    ? authHeader.slice(7)
    : authHeader || null;

  if (!token) {
    return res.status(401).json({ error: 'Missing bearer token.' });
  }

  // Try a real Supabase session first.
  const { data: supabaseUser } = await supabaseAdmin.auth.getUser(token);
  if (supabaseUser?.user) {
    const { data: profile, error } = await supabaseAdmin
      .from('profiles')
      .select('id')
      .eq('auth_user_id', supabaseUser.user.id)
      .maybeSingle();

    if (error) return res.status(500).json({ error: 'Failed to resolve profile.' });

    if (profile) {
      req.user = { id: profile.id };
      return next();
    }

    // Supabase Auth user exists but the trigger hasn't caught up yet
    // (or ran before this backend existed) — create the row now.
    const { data: created, error: createError } = await supabaseAdmin
      .from('profiles')
      .insert({
        auth_user_id: supabaseUser.user.id,
        email: supabaseUser.user.email,
      })
      .select('id')
      .single();

    if (createError) return res.status(500).json({ error: 'Failed to create profile.' });
    req.user = { id: created.id };
    return next();
  }

  // Fall back to the legacy token scheme.
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');

  const { data: existingSession } = await supabaseAdmin
    .from('legacy_sessions')
    .select('profile_id')
    .eq('token_hash', tokenHash)
    .maybeSingle();

  if (existingSession) {
    await supabaseAdmin
      .from('legacy_sessions')
      .update({ last_seen_at: new Date().toISOString() })
      .eq('token_hash', tokenHash);
    req.user = { id: existingSession.profile_id };
    return next();
  }

  // First time we've seen this token — mint a profile for it.
  const { data: newProfile, error: newProfileError } = await supabaseAdmin
    .from('profiles')
    .insert({})
    .select('id')
    .single();

  if (newProfileError) {
    return res.status(500).json({ error: 'Failed to create a session.' });
  }

  await supabaseAdmin.from('legacy_sessions').insert({
    token_hash: tokenHash,
    profile_id: newProfile.id,
  });

  req.user = { id: newProfile.id };
  next();
}

module.exports = { requireAppUser };

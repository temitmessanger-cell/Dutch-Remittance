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

  // Everything below this point used to have no try/catch at all —
  // any Supabase call throwing (a transient network blip, a
  // malformed/expired token that supabaseAdmin.auth.getUser()
  // rejects with an exception rather than an error field, an insert
  // violating a constraint) escaped straight past Express's normal
  // routing and landed in the browser as a bare, unformatted 500
  // with no JSON body — exactly the symptom reported against
  // POST /api/v1/collections/otp. Wrapped in try/catch now so every
  // failure here returns the same clean JSON shape every other route
  // in this backend does, via errorHandler.js.
  try {
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
  } catch (err) {
    // Same normalized shape every other error in this backend
    // returns, instead of a bare, unformatted 500.
    res.status(500).json({
      error: 'Could not verify your session right now. Please try again.',
      details: process.env.NODE_ENV !== 'production' ? err.message : undefined,
    });
  }
}

/// Same identity resolution as requireAppUser, but never blocks the
/// request — if no token is present (or resolution fails for any
/// reason), req.user is simply left undefined and the route
/// continues as a guest. For endpoints like quotation lookups that
/// are useful to browse without an account, but that benefit from
/// knowing who's asking when they are logged in (e.g. checking
/// whether they already have a bank account for a Klasha-fallback
/// currency — see paymentRouter.js).
async function optionalAppUser(req, res, next) {
  const authHeader = req.headers.authorization || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : authHeader || null;

  if (!token) {
    return next();
  }

  try {
    const { data: supabaseUser } = await supabaseAdmin.auth.getUser(token);
    if (supabaseUser?.user) {
      const { data: profile } = await supabaseAdmin
        .from('profiles')
        .select('id')
        .eq('auth_user_id', supabaseUser.user.id)
        .maybeSingle();
      if (profile) {
        req.user = { id: profile.id };
      }
      return next();
    }

    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const { data: existingSession } = await supabaseAdmin
      .from('legacy_sessions')
      .select('profile_id')
      .eq('token_hash', tokenHash)
      .maybeSingle();
    if (existingSession) {
      req.user = { id: existingSession.profile_id };
    }
    next();
  } catch (_) {
    // Any resolution failure here degrades to "treat as guest" rather
    // than blocking the request — this middleware's whole point is to
    // never be the reason a quotation lookup fails.
    next();
  }
}

module.exports = { requireAppUser, optionalAppUser };

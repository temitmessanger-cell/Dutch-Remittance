const express = require('express');
const { supabaseAdmin, supabaseAuth } = require('../supabaseClient');
const { requireAppUser } = require('../middleware/requireAppUser');

const router = express.Router();

/**
 * Real auth, backed by Supabase Auth (auth.users + GoTrue) — the old
 * custom backend is gone, so this is now the only identity system.
 * Every signup/login below returns a genuine Supabase session token
 * as `authorization_token`, which requireAppUser.js already knows how
 * to verify the proper way (not the legacy-token hash fallback, which
 * only exists for sessions minted before this migration).
 */

function shapeUser(profile, authUser) {
  return {
    id: profile.id,
    dutchRemitId: profile.dutch_remit_id,
    fullname: `${profile.first_name || ''} ${profile.last_name || ''}`.trim(),
    first_name: profile.first_name,
    last_name: profile.last_name,
    username: profile.username,
    email: profile.email || authUser?.email,
    phone_number: profile.phone_number,
    address: profile.address,
    country: profile.country,
    avatar: profile.avatar_url,
    // Legacy UI (UserLoginStateProvider.initializeBankBalance) expects
    // a bankDetails array to seed a starting balance from. This is a
    // safe placeholder immediately overwritten by the real Eversend
    // balance sync on the Home screen (syncBalanceFromEversend).
    bankDetails: [
      { bankName: 'Dutch Remit Wallet', bankBalance: '0.00', currency: 'USD' },
    ],
  };
}

// POST /Dutch Remit/v1/user/register
// Body: { fullname, address, emailId, password, bankAccount }
// (exact shape sign_up_steps.dart already sends)
router.post('/user/register', async (req, res) => {
  const { fullname, address, emailId, password } = req.body || {};

  if (!fullname || !emailId || !password) {
    return res.json({ error: 'Full name, email and password are required.' });
  }
  if (password.length < 6) {
    return res.json({ error: 'Password must be at least 6 characters.' });
  }

  const nameParts = fullname.trim().split(/\s+/);
  const firstName = nameParts[0];
  const lastName = nameParts.slice(1).join(' ') || nameParts[0];

  const { data: created, error: createError } = await supabaseAdmin.auth.admin.createUser({
    email: emailId,
    password,
    email_confirm: true,
  });

  if (createError) {
    const message = createError.message?.toLowerCase().includes('already registered')
      ? 'An account with this email already exists.'
      : createError.message || 'Could not create account.';
    return res.json({ error: message });
  }

  const authUser = created.user;

  // The `on_auth_user_created` trigger (see schema.sql) already
  // inserts a bare profiles row — update it with everything the
  // sign-up form actually collected, rather than inserting a second
  // row and racing the trigger.
  const { data: profile, error: profileError } = await supabaseAdmin
    .from('profiles')
    .update({ first_name: firstName, last_name: lastName, address, email: emailId })
    .eq('auth_user_id', authUser.id)
    .select()
    .single();

  if (profileError || !profile) {
    return res.json({ error: 'Account created, but the profile could not be saved. Please try logging in.' });
  }

  const { data: session, error: signInError } = await supabaseAuth.auth.signInWithPassword({
    email: emailId,
    password,
  });
  if (signInError || !session?.session) {
    return res.json({ error: 'Account created — please log in.' });
  }

  res.json({
    authorization_token: session.session.access_token,
    user: shapeUser(profile, authUser),
  });
});

// POST /Dutch Remit/v3/user/login
// Body: { userInput, password } — userInput is treated as an email.
router.post('/user/login', async (req, res) => {
  const { userInput, password } = req.body || {};
  if (!userInput || !password) {
    return res.json({ error: 'Enter your email and password.' });
  }

  const { data: session, error } = await supabaseAuth.auth.signInWithPassword({
    email: userInput,
    password,
  });

  if (error || !session?.session) {
    return res.json({ error: 'Incorrect email or password.' });
  }

  const { data: profile, error: profileError } = await supabaseAdmin
    .from('profiles')
    .select('*')
    .eq('auth_user_id', session.user.id)
    .maybeSingle();

  if (profileError || !profile) {
    return res.json({ error: "We couldn't find your profile. Please contact support." });
  }

  res.json({
    authorization_token: session.session.access_token,
    user: shapeUser(profile, session.user),
  });
});

// GET /Dutch Remit/v3/user/:userId — session restore on app launch
// (main.dart's fetchUserId). `:userId` is `profiles.id`.
router.get('/user/:userId', requireAppUser, async (req, res) => {
  const { data: profile, error } = await supabaseAdmin
    .from('profiles')
    .select('*')
    .eq('id', req.params.userId)
    .maybeSingle();

  if (error || !profile) {
    return res.json({ error: 'Session expired. Please log in again.' });
  }

  res.json({ user: shapeUser(profile, null) });
});

// GET /Dutch Remit/app — simple app-info payload (credits_screen.dart).
router.get('/app', (req, res) => {
  res.json({
    name: 'Dutch Remit',
  });
});

// --- Passwordless email-OTP auth (login and signup both use this —
// the app never collects a password anymore). Supabase Auth mints and
// verifies the code itself (signInWithOtp / verifyOtp); this backend
// just proxies those two calls and shapes the profile response the
// same way the old password endpoints did. ---

// POST /api/v1/auth/otp/request — Body: { email, purpose: 'signup' | 'login' }
router.post('/otp/request', async (req, res) => {
  const { email, purpose } = req.body || {};
  if (!email) {
    return res.json({ error: 'Enter your email address.' });
  }

  const shouldCreateUser = purpose === 'signup';

  const { error } = await supabaseAuth.auth.signInWithOtp({
    email,
    options: { shouldCreateUser },
  });

  if (error) {
    const message = !shouldCreateUser && /not found|signups not allowed|user not found/i.test(error.message || '')
      ? 'No account found with that email. Please sign up.'
      : (error.message || 'Could not send a code. Please try again.');
    return res.json({ error: message });
  }

  res.json({ message: 'Code sent — check your email.' });
});

// POST /api/v1/auth/otp/verify — Body: { email, token, fullname?, address? }
// fullname/address are only sent by the sign-up flow, to finish
// filling in the profile row the moment the account is confirmed.
router.post('/otp/verify', async (req, res) => {
  const { email, token, fullname, address } = req.body || {};
  if (!email || !token) {
    return res.json({ error: 'Enter the code we emailed you.' });
  }

  const { data, error } = await supabaseAuth.auth.verifyOtp({
    email,
    token,
    type: 'email',
  });

  if (error || !data?.session || !data?.user) {
    return res.json({ error: 'That code is invalid or has expired.' });
  }

  const authUser = data.user;

  if (fullname || address) {
    const update = { email };
    const nameParts = (fullname || '').trim().split(/\s+/).filter(Boolean);
    if (nameParts.length) {
      update.first_name = nameParts[0];
      update.last_name = nameParts.slice(1).join(' ') || nameParts[0];
    }
    if (address) update.address = address;
    await supabaseAdmin.from('profiles').update(update).eq('auth_user_id', authUser.id);
  }

  const { data: profile, error: profileError } = await supabaseAdmin
    .from('profiles')
    .select('*')
    .eq('auth_user_id', authUser.id)
    .maybeSingle();

  if (profileError || !profile) {
    return res.json({ error: "We couldn't find your profile. Please try again." });
  }

  res.json({
    authorization_token: data.session.access_token,
    user: shapeUser(profile, authUser),
  });
});

// --- Username selection (replaces the old Socket.IO "username
// request"/"username status" flow — see choose_username_screen.dart,
// now rewritten to call these instead of opening a socket). ---

// GET /api/v1/auth/check-username?username=xxx
router.get('/check-username', async (req, res) => {
  const username = (req.query.username || '').toString().trim();
  if (username.length < 3) {
    return res.json({ available: false, reason: 'Username must be at least 3 characters.' });
  }
  const { data, error } = await supabaseAdmin
    .from('profiles')
    .select('id')
    .ilike('username', username)
    .maybeSingle();

  if (error) return res.status(500).json({ error: 'Could not check username.' });
  res.json({ available: !data });
});

// POST /api/v1/auth/set-username — Body: { username }
router.post('/set-username', requireAppUser, async (req, res) => {
  const username = (req.body?.username || '').toString().trim();
  if (username.length < 3) {
    return res.status(400).json({ error: 'Username must be at least 3 characters.' });
  }

  const { data: taken } = await supabaseAdmin
    .from('profiles')
    .select('id')
    .ilike('username', username)
    .neq('id', req.user.id)
    .maybeSingle();

  if (taken) {
    return res.status(409).json({ error: 'That username is already taken.' });
  }

  const { data: profile, error } = await supabaseAdmin
    .from('profiles')
    .update({ username })
    .eq('id', req.user.id)
    .select()
    .single();

  if (error) return res.status(500).json({ error: 'Could not save username.' });
  res.json({ user: shapeUser(profile, null) });
});

module.exports = router;

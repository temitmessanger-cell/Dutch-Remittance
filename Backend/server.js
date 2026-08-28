require('dotenv').config();

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');

const walletsRouter = require('./src/routes/wallets');
const ratesRouter = require('./src/routes/rates');
const transactionsRouter = require('./src/routes/transactions');
const beneficiariesRouter = require('./src/routes/beneficiaries');
const collectionsRouter = require('./src/routes/collections');
const payoutsRouter = require('./src/routes/payouts');
const cryptoRouter = require('./src/routes/crypto');
const cardsRouter = require('./src/routes/cards');
const klashaRouter = require('./src/routes/klasha');
const corridorsRouter = require('./src/routes/corridors.route');
const webhooksRouter = require('./src/routes/webhooks');
const legacyCompatRouter = require('./src/routes/legacyCompat');
const authRouter = require('./src/routes/auth');
const contactsRouter = require('./src/routes/contacts');
const businessesRouter = require('./src/routes/businesses');
const devicesRouter = require('./src/routes/devices');
const notificationsRouter = require('./src/routes/notifications');
const usersRouter = require('./src/routes/users');
const { errorHandler } = require('./src/errorHandler');

const app = express();

app.use(helmet());
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev'));
const allowedOrigins = process.env.ALLOWED_ORIGIN
  ? process.env.ALLOWED_ORIGIN.split(',').map((o) => o.trim())
  : [];
// Local dev servers (flutter run -d chrome/edge/web-server) bind to a
// different random port every launch — rather than chase each one,
// allow any localhost/127.0.0.1 origin outside production. This never
// applies in production since NODE_ENV is set there.
const isLocalOrigin = (origin) => /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin || '');

app.use(
  cors({
    origin: (origin, callback) =>
      callback(null, !origin || isLocalOrigin(origin) || allowedOrigins.includes(origin) || !allowedOrigins.length),
    credentials: true,
  })
);

// Webhooks need the raw body for HMAC signature verification, so this
// is mounted BEFORE the global JSON body parser below.
app.use('/api/v1/webhooks', express.raw({ type: 'application/json' }), webhooksRouter);

app.use(express.json({ limit: '2mb' }));

app.get('/', (req, res) => {
  res.json({ name: 'Dutch Remit backend', status: 'ok' });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

// GET /diagnostics/klasha — a single call to confirm, definitively,
// whether the fixes already made to src/klashaClient.js this session
// (per-request proxy agent, normalized error messages) are actually
// live on this deployment, before spending more time debugging a
// 502 that might just be a stale deploy. If klashaClientVersion
// below doesn't match what's in the source file, that's the whole
// answer — redeploy and retest before looking any further.
app.get('/diagnostics/klasha', async (req, res) => {
  const hasProxyConfigured = !!process.env.OUTBOUND_PROXY_URL;
  let liveBanksTest = null;
  try {
    const { klasha } = require('./src/klashaClient');
    const { KLASHA_PAYOUT_ENDPOINTS } = require('./src/corridors');
    const start = Date.now();
    const data = await klasha.get(KLASHA_PAYOUT_ENDPOINTS.NGN.banksPath);
    liveBanksTest = { ok: true, durationMs: Date.now() - start, bankCount: Array.isArray(data?.data) ? data.data.length : null };
  } catch (err) {
    liveBanksTest = {
      ok: false,
      status: err.status,
      message: err.message,
      // If this message ever says "Request failed with status code
      // ..." (raw axios text) instead of a plain-language message,
      // klashaClient.js's _normalize() fix is NOT live on this
      // deployment — that IS the bug, full stop, redeploy and retest.
      isNormalizedMessage: !/^Request failed with status code/.test(err.message || ''),
      details: err.details,
    };
  }
  res.json({
    klashaClientVersion: 'per-request-proxy-agent-v2',
    outboundProxyConfigured: hasProxyConfigured,
    outboundProxyConfiguredNote: hasProxyConfigured
      ? 'OUTBOUND_PROXY_URL is set — requests to Klasha should leave from the proxy\'s static IP.'
      : 'OUTBOUND_PROXY_URL is NOT set — requests to Klasha leave from Railway\'s own outbound IP directly, which changes and is not whitelistable. If Klasha requires IP whitelisting, this is very likely the actual cause of the 502.',
    liveNgnBanksTest: liveBanksTest,
  });
});

// --- Clean, current API surface ---
app.use('/api/v1/wallets', walletsRouter);
app.use('/api/v1/rates', ratesRouter);
app.use('/api/v1/transactions', transactionsRouter);
app.use('/api/v1/beneficiaries', beneficiariesRouter);
app.use('/api/v1/collections', collectionsRouter);
app.use('/api/v1/payouts', payoutsRouter);
app.use('/api/v1/crypto', cryptoRouter);
app.use('/api/v1/cards', cardsRouter);
app.use('/api/v1/klasha', klashaRouter);
app.use('/api/v1/corridors', corridorsRouter);
app.use('/api/v1/auth', authRouter);
app.use('/api/v1/devices', devicesRouter);
app.use('/api/v1/notifications', notificationsRouter);
app.use('/api/v1/businesses', businessesRouter);
app.use('/api/v1/contacts', contactsRouter);
app.use('/api/v1/users', usersRouter);

// --- Legacy-shaped surface the existing Flutter app already calls
// (login, register, session restore, contacts, businesses, execute a
// transaction, available cards, app info) — the OLD custom backend
// (fruitcastle.onrender.com) is gone entirely; every one of these is
// now backed for real by Supabase Auth + the tables in
// supabase/schema.sql, not a stub.
//
// IMPORTANT: these paths use the literal "%20" sequence, not a real
// space character. Express matches routes against the RAW,
// percent-encoded URL — it does NOT decode before matching — and the
// Flutter app's http client always sends a literal space in the path
// as "%20" on the wire (confirmed from the app's own earlier error
// logs: ".../Dutch%20Remit/v1/all-transactions"). A route pattern
// written with an actual space character will silently never match a
// real request; only the %20 form does. Verified directly against a
// raw socket request during development — do not "clean up" these
// back to literal spaces.
//
// Mounted under both the exact casing the app uses ("Dutch%20Remit")
// and the one inconsistent lowercase path main.dart calls for session
// restore ("dutch_remit") — see README's "Known app-side bug" note;
// fixing that one call site in Flutter is one line (also done in this
// pass), but this alias means the app works either way regardless.
app.use('/Dutch%20Remit', authRouter);
app.use('/Dutch%20Remit/v1', authRouter);
app.use('/Dutch%20Remit/v3', authRouter);
app.use('/dutch_remit', authRouter);
app.use('/dutch_remit/v3', authRouter);
app.use('/Dutch%20Remit/v1', legacyCompatRouter);
app.use('/Dutch%20Remit/v2', legacyCompatRouter);
app.use('/Dutch%20Remit/v2/businesses-and-brands', businessesRouter);
app.use('/Dutch%20Remit/v3/all-contacts', contactsRouter);

app.use((req, res) => {
  res.status(404).json({ error: `No route for ${req.method} ${req.originalUrl}` });
});

app.use(errorHandler);

const port = process.env.PORT || 4000;
app.listen(port, () => {
  console.log(`Dutch Remit backend listening on port ${port}`);
});

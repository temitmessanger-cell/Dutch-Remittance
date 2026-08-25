# Dutch Remit — Launch setup

Everything needed to take this from "runs locally" to "live at
dutchremit.dubiabank.com" — what's already done, what you do next,
and what to send back so the remaining pieces can be finished.

## Current status (updated live)

- ✅ **Code repository**: pushed to
  https://github.com/temitmessanger-cell/Dutch-Remittance
- ✅ **Backend**: deployed and verified live at
  `https://dutch-remittance-production.up.railway.app` — health
  check and a real Supabase-backed query both confirmed working.
- ✅ **Eversend webhook**: configured, pointing at the live backend,
  secret set in Railway.
- ⚠️ **Klasha credentials**: still placeholder values in Railway's
  variables (`KLASHA_SECRET_KEY`, `KLASHA_ENCRYPTION_KEY`,
  `KLASHA_BUSINESS_ID`) — everything Eversend-related works; anything
  routed through Klasha (South Africa payouts, NGN/GHS virtual
  accounts) will fail until these are filled in with real values.
- ✅ **Production web build**: built locally with
  `--dart-define=API_BASE_URL=https://dutch-remittance-production.up.railway.app`,
  confirmed the URL is actually embedded in the compiled output.
- ⏳ **Netlify deploy**: in progress — pending Netlify CLI login.

## The shape of the deployment

- **Frontend** (`dutchremit.dubiabank.com`) — the Flutter web build,
  hosted on Netlify (already configured — see `netlify.toml`). This
  domain serves the app only.
- **Backend** (a separate URL, e.g.
  `dutch-remit-backend.up.railway.app`) — the Node/Express API in
  `Backend/`, hosted on Railway. The app talks to it over HTTPS; it's
  never on the same domain.

This split is deliberate: it's exactly why hosting the frontend can't
"disturb" auth or the backend — they're two independent deployments
with no shared state. Redeploying the app never touches the backend or
its database, and vice versa.

---

## Part 1 — Deploy the backend to Railway

### 1. Create the Railway project
1. Go to [railway.app](https://railway.app) and sign in (GitHub login
   is easiest since you'll connect a repo next).
2. **New Project → Deploy from GitHub repo** → pick this repo.
3. Railway will ask for a **root directory** — set it to `Backend`
   (not the repo root — the Flutter app lives outside it and isn't
   part of this service).
4. Railway auto-detects Node via `package.json` and will run
   `npm install` + `npm start`. `Backend/railway.json` (already in
   the repo) also pins the start command and points Railway's
   healthcheck at `GET /health`, which the server already implements.

### 2. Set environment variables
In the Railway project → **Variables** tab, add every key from
`Backend/.env.example`:

| Variable | Value |
|---|---|
| `NODE_ENV` | `production` |
| `ALLOWED_ORIGIN` | `https://dutchremit.dubiabank.com` |
| `EVERSEND_BASE_URL` | `https://api.eversend.co/v1` |
| `EVERSEND_CLIENT_ID` | *(your real value — see "What to send back" below)* |
| `EVERSEND_CLIENT_SECRET` | *(your real value)* |
| `EVERSEND_WEBHOOK_SECRET` | *(set after step 4 below)* |
| `SUPABASE_URL` | *(your real value)* |
| `SUPABASE_SERVICE_ROLE_KEY` | *(your real value)* |
| `SUPABASE_ANON_KEY` | *(your real value)* |
| `KLASHA_BASE_URL` | `https://api.klasha.com` |
| `KLASHA_PUBLIC_KEY` | *(your real value)* |
| `KLASHA_SECRET_KEY` | *(your real value)* |
| `KLASHA_ENCRYPTION_KEY` | *(your real value — must be exactly 24 characters)* |
| `KLASHA_BUSINESS_ID` | *(your real value)* |

Don't set `PORT` — Railway injects it automatically, and
`Backend/server.js` already reads `process.env.PORT` first.

### 3. Deploy and get your backend URL
Railway deploys automatically once variables are set. Under
**Settings → Networking**, click **Generate Domain** to get a public
URL like `dutch-remit-backend.up.railway.app`. Test it:
```
curl https://<your-railway-url>/health
```
Should return `{"status":"ok","time":"..."}`.

### 4. Configure the Eversend webhook
In the Eversend dashboard → Settings → Developers → Webhook, set the
URL to:
```
https://<your-railway-url>/api/v1/webhooks/eversend
```
Copy the webhook secret it gives you into Railway's
`EVERSEND_WEBHOOK_SECRET` variable, then redeploy (Railway redeploys
automatically when you change a variable).

### 5. Run the database schema
Supabase dashboard → SQL Editor → paste the full contents of
`Backend/supabase/schema.sql` → **Run**. Safe to re-run any time
(every statement is idempotent).

---

## Part 2 — Point the app at the real backend

The app never hardcodes the backend URL — `lib/resources/api_constants.dart`
reads it at build time:

- **Local testing** (unchanged, no flag needed):
  ```
  flutter run -d chrome
  ```
  Uses `http://localhost:4000` automatically.

- **Production build**, once you have the Railway URL from Part 1:
  ```
  flutter build web --dart-define=API_BASE_URL=https://<your-railway-url>
  ```
  This is the one command that actually matters for launch — it's how
  the same source code becomes a build that talks to the real backend,
  with zero source changes and nothing to remember to revert.

Deploy the resulting `build/web` folder to Netlify (already configured
via `netlify.toml` to serve `build/web` and proxy `/api/plaid/*` to
its own functions — unrelated to the Backend/ Node service).

---

## What to send back / do yourself

Nothing further is needed from me for deployment itself — Parts 1 and
2 above are the complete path to a live app. What's still on you:

1. **Real credentials** for the Variables table in Part 1, step 2, if
   you haven't already filled them into Railway. (If these were the
   same ones pasted in earlier chat messages, rotate them from each
   provider's dashboard first — see "Security notes" in
   `Backend/README.md`. Credentials shared in plaintext chat should be
   treated as already exposed.)
2. **Run `supabase/schema.sql`** against your real Supabase project
   (Part 1, step 5) — nothing in the backend works without this.
3. **One real end-to-end test** once deployed: a real deposit and a
   real payout. This environment's network egress can't reach
   Eversend/Klasha to verify live calls, so this hasn't been tested
   against production traffic — see the honesty note in
   `Backend/README.md`.
4. **Klasha virtual-account flow specifically** — the two-hop
   "Eversend wallet → virtual account → final payout" orchestration
   (see `PRICING.md` and `paymentRouter.js`) is built from Klasha's
   documented endpoints but has never been exercised against a live
   Klasha account from here. Test one real virtual-account creation
   and one real send through it before relying on it for real users.

## Local testing safety

Everything in this repo is now safe to test locally without any risk
to production:
- The app defaults to `localhost:4000` unless you explicitly pass
  `--dart-define=API_BASE_URL=...` at build time — a normal
  `flutter run` never touches the real backend.
- The backend's CORS config always allows `localhost`/`127.0.0.1`
  origins regardless of environment, on top of the explicit
  `ALLOWED_ORIGIN` allowlist — local dev servers work without any
  config changes, and this never widens what production accepts from
  the public internet.
- `.env` (with real credentials) is git-ignored — it only exists on
  your machine and in Railway's Variables tab, never in the repo.

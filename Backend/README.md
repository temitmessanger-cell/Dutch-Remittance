# Dutch Remit — Backend

A small Node/Express service that sits between the Flutter app and
Eversend, and mirrors user-facing data (transactions, beneficiaries,
cards) into Supabase. Lives outside `lib/` on purpose — this is a
separate deployable, not part of the Flutter build.

```
Backend/
├── server.js                  # entry point, mounts every route
├── src/
│   ├── eversendClient.js      # token caching + generic Eversend request wrapper
│   ├── supabaseClient.js      # service_role Supabase client (server-only)
│   ├── corridors.js           # confirmed corridor/country reference data
│   ├── errorHandler.js
│   ├── middleware/
│   │   └── requireSupabaseUser.js   # verifies the app's Supabase session token
│   └── routes/
│       ├── wallets.js
│       ├── rates.js           # exchange + payout quotations (the numbers behind every quote screen)
│       ├── transactions.js
│       ├── beneficiaries.js
│       ├── collections.js     # deposits / fiat-in
│       ├── payouts.js         # withdrawals, sends, transfers
│       ├── crypto.js
│       ├── cards.js           # virtual cards
│       ├── corridors.route.js
│       ├── webhooks.js        # Eversend webhook receiver (HMAC-verified)
│       └── legacyCompat.js    # keeps the app's existing `/Dutch Remit/v1/...` calls working
├── supabase/schema.sql        # run once against your Supabase project
├── .env.example
├── render.yaml
└── Procfile
```

## The old backend is gone — this replaces it entirely

Earlier passes at this project kept `fruitcastle.onrender.com` (a
third-party host outside your control, and unreachable — that's what
was throwing the `ClientException: Failed to fetch` error) as the
target for the app's pre-existing `/Dutch Remit/...` calls, with this
backend only covering the new `/api/v1/...` surface alongside it.
That's no longer true. **Every** legacy call the Flutter app makes —
login, registration, session restore, contacts, the business
directory, paying a contact, available cards, app info — is now
implemented for real here, backed by Supabase, with no dependency on
any other host. Point `ApiConstants.baseUrl` at this backend and
nothing else is needed.

### A routing bug worth knowing about

Every one of those legacy paths contains a literal space
("`/Dutch Remit/v1/...`"). **Express matches routes against the raw,
percent-encoded URL — it does not decode before matching** — and the
Flutter app's HTTP client always sends that space as `%20` on the
wire (confirmed straight from the app's own earlier error log:
`.../Dutch%20Remit/v1/all-transactions`). A route registered with an
actual space character silently never matches a real request; it has
to be registered with the literal `%20` sequence instead. Every
legacy route in `server.js` is written that way on purpose — do not
"clean up" `%20` back into a plain space, it will break instantly and
silently (you'll get 404s, not an error you'd notice at a glance).

### A pre-existing bug fixed on the Flutter side too

`main.dart`'s session-restore call used a different path shape than
every other legacy call in the app — `/dutch_remit/v3/user/$userId`
(lowercase, underscore) instead of `/Dutch Remit/v3/user/$userId`
(capitalized, space). That's fixed in `lib/main.dart` in this pass.
The backend still accepts both forms (`server.js` mounts the auth
router under `dutch_remit` as an alias too), so nothing breaks even
if you're testing against an older build of the app.

## Why this shape

Eversend's API (docs: https://eversend.readme.io/reference/api-overview,
base URL `https://api.eversend.co/v1`) requires a `clientId`/`clientSecret`
pair to mint a bearer token. That secret can never live in the Flutter
app — anyone could decompile it out of the APK. This backend holds it,
mints and caches the token server-side, and exposes a clean set of
routes the app calls instead, each one requiring the user's own
Supabase session token so requests are tied to a real signed-in user.

## What's wired up end-to-end in the app right now

- **Login, registration, session restore:** real Supabase Auth
  (`auth.users` + GoTrue) — the old backend's stand-in for these is
  gone. Every new signup/login returns a genuine Supabase session
  token, not the legacy-token hash bridge (that fallback still exists
  in `requireAppUser.js`, but only matters for sessions minted before
  this migration).
- **Username selection:** the old Socket.IO "username request"/
  "username status" flow (which needed a live WebSocket server that
  never existed here) is replaced with a debounced REST check
  (`choose_username_screen.dart` → `GET /api/v1/auth/check-username`)
  and an actual server-side reservation on confirm
  (`POST /api/v1/auth/set-username`) — previously the chosen username
  was only ever saved to local device storage, so nothing stopped two
  people picking the same one.
- **Contacts, business directory, "pay a contact" flow:** all three
  now hit real Supabase-backed routes instead of a dead host.
- **Deposit (Mobile Money / Orange Money):** `top_up_screen.dart` →
  `mobile_money_deposit_screen.dart` → real OTP request, code entry,
  confirmed collection, and a receipt showing the refreshed Eversend
  wallet balance. Not a simulated instant credit.
- **Withdrawal (Mobile Money / Orange Money):** `withdraw_screen.dart`
  → `mobile_money_withdrawal_screen.dart` → destination country,
  recipient name/phone, live quote, confirmed payout via the unified
  `POST /api/v1/payouts/send` (auto-routes to Eversend or Klasha).
- **Diaspora to Africa / Africa to Africa / Quick Transfer sends:**
  `africa_corridor_screen.dart`'s "Send money"/"Continue" calls the
  same unified payout endpoint — real send, real provider routing,
  real receipt.
- **Home balance:** syncs from `GET /api/v1/wallets` on load, with a
  spinner next to the currency pill, and a safe silent fallback to
  the locally-tracked balance if the backend isn't reachable yet.
- **Card creation:** `wallet_screen.dart`'s "Create a Virtual Card" →
  `create_virtual_card_screen.dart` → real 3-step flow (identity KYC
  → design & funding → issue) against Eversend's actual Cards API.
  No raw card number/CVV ever passes through this backend.
- **User tracking:** every one of the above writes to Supabase, keyed
  off a real `profiles.id`.

## What's NOT wired yet (the honest remainder)

- **Global Transfer** (the general 31-currency "any pair" tab) still
  only records a local receipt on send — it doesn't yet collect
  recipient/bank details, so there's nothing to hand the real payout
  endpoint. Wiring it for real needs a recipient-collection step
  first (similar to what `mobile_money_withdrawal_screen.dart` already
  does), then the same `POST /api/v1/payouts/send` call.
- **Beneficiary management UI** (the Recipient tab) still manages
  contacts via `database/contacts_storage.dart` (local) rather than
  the real `/api/v1/beneficiaries` + `/Dutch Remit/v3/all-contacts`
  routes — both exist and are ready, the screen just isn't calling
  them yet.
- **Klasha bank-list / account-resolution UI** — the backend routes
  (`GET /api/v1/klasha/banks/:currency`, `POST /api/v1/klasha/resolve-account`)
  exist, and `africa_corridor_screen.dart`'s "Bank account" payout
  method now shows a real bank picker built on `/klasha/banks/:currency`
  — but the actual send still isn't wired for that method (see the
  screen's own validation message); only Mobile money sends end-to-end
  today.
- **`resolveProvider`/Klasha fallback flow, corrected**: Eversend is
  tried first for every deposit/payout, always. If a currency isn't
  in Eversend's coverage, the app checks whether the user has a
  matching-currency bank account (Klasha virtual account); if not, it
  throws `needsVirtualAccount` so the app prompts a one-time setup;
  if they do, the transfer completes automatically through that
  account and Klasha's payout rail, with Klasha never surfaced as a
  visible "provider" anywhere the user can see (transaction records
  always say `provider: 'eversend'`, even when Klasha executed the
  actual payout underneath — the raw Klasha response is still kept in
  `raw_response` for support/debugging). This replaces an earlier,
  incorrect version of this pass where Klasha was wired as a second
  peer routing choice by currency, bypassing the virtual-account step
  entirely — that was wrong and has been corrected.
  **Important real limitation**: the virtual-account creation route
  (`POST /api/v1/klasha/virtual-account`) only works for NGN and GHS
  (`KLASHA_VIRTUAL_ACCOUNT_CURRENCIES` in `src/corridors.js`) — Klasha's
  own docs only confirm NGN for virtual-account creation. `resolveProvider`
  will correctly identify 8 more currencies (KES, XAF, XOF, UGX, ZMW,
  TZS, RWF, ZAR) as Klasha-payout-capable, and `executePayout` will
  correctly throw `needsVirtualAccount` for them, but there's no
  screen yet that can act on that error for anything outside NGN/GHS
  — `virtual_accounts_screen.dart`'s currency picker is NGN/GHS only.
  Extending Klasha virtual-account creation to more currencies (if
  Klasha's dashboard actually supports it) and this screen's currency
  list must happen together.
- **KlashaWire** (`KLASHA_WIRE_*` constants in `src/corridors.js`) is
  a genuinely different product from momo/bank payouts — a $500–$50,000
  business-style wire transfer settling in hard currencies (USD, EUR,
  CNY, GBP, etc.) to 120+ countries in 1–4 business days. `wire_transfer_request_screen.dart`
  and `POST /api/v1/klasha/wire` exist now, but the wire route
  deliberately does NOT call any Klasha endpoint — Klasha's public
  docs confirm the product exists but never publish its API request
  shape, so the route records the request as `pending_manual` in
  `transactions` instead of guessing at a path. Klasha
  publishes a restricted/not-supported destination list rather than
  an enumerable "all 120+ countries" array, so a real country picker
  for it should call Klasha's own live endpoint rather than a
  hardcoded list here, which would go stale.
- **Crypto withdrawal** (`POST /api/v1/crypto/withdraw`) is now built
  against Eversend's actually-confirmed API. An earlier pass guessed
  at a direct crypto-send endpoint; Eversend's full API reference
  confirms their crypto product is receive-only (Fetch Asset Chains,
  Create/Fetch Crypto Addresses, Fetch Transactions — no
  withdraw/send). Their own docs describe the real intended flow:
  exchange the coin to fiat, then send via the normal payout rail —
  so this route now calls the confirmed `POST /exchanges/quotation`
  and `POST /exchanges` endpoints, and `withdraw_screen.dart` hands
  off to `GlobalBankTransferScreen` to complete the send, instead of
  asking for a destination crypto wallet address the API could never
  act on.
- **Klasha webhook signature verification** — `POST /api/v1/webhooks/klasha`
  logs and syncs every event but doesn't verify a signature (unlike
  the Eversend one, which does). Klasha's published docs cover
  request-payload encryption, not webhook verification — if their
  dashboard shows a signing secret/header when you configure the
  webhook, tell me what it's called and I'll add verification to
  match.
- **`devices` / `notifications` tables** — schema and routes
  (`POST /api/v1/devices`, `GET/PATCH /api/v1/notifications`) exist;
  the Payments tab has a real Notifications upper nav wired to
  `GET/PATCH /api/v1/notifications`, and both webhook handlers
  (`src/routes/webhooks.js`) now write a plain-language notification
  when a transaction resolves to success or failure — the write side
  that was missing earlier this session is filled in now. `devices`
  still has no writer anywhere.
- Real Eversend/Klasha/Supabase credentials couldn't be exercised
  against live traffic from this environment (its network egress is
  restricted to a small allowlist that doesn't include
  `api.eversend.co`, `api.klasha.com`, or your Supabase project) —
  everything here is verified via `node --check`, a local server
  boot, and route-shape testing (including a raw-socket test that
  caught the `%20` routing bug above), not a live end-to-end
  transaction. Run through one real deposit and one real payout
  yourself once deployed, before pointing real users at it.

## Cards — creation, linking, and card-to-card transfers are all real

**Card creation/issuance**, backed by Eversend's actual documented
Cards API (https://eversend.readme.io/reference/create-a-card-user
and .../create-a-card) — confirmed directly against their API
reference, not guessed:

1. `POST /api/v1/cards/user` — a one-time KYC profile per person
   (name, email, phone, address, government ID: National ID,
   Passport, or Driving License — or, if the user chooses "proceed
   without KYC" for a $1.50 fee, a synthesized identity: idType 'ID'
   for African countries / 'FOREIGN' otherwise, with a generated
   unique cardholder reference — see `card_kyc_identities` in
   `supabase/schema.sql`). Eversend requires this before it will issue
   anyone a card.
2. `POST /api/v1/cards` — issues the actual card: a title, color, brand
   (visa/mastercard), an initial funding amount, and a $3.50 one-time
   or $1.10/month card-creation fee (`cardFeeType`).

No raw card number or CVV passes through this backend in either
direction for *issued* cards — Eversend generates and holds the card;
the app only ever references it by `cardId`.
`create_virtual_card_screen.dart` implements this as a real 3-step
flow (identity → design & funding → issue).

**Card *linking*** (`add_card_screen.dart`, gated by
`card_link_verification_screen.dart`) — attaching a card the user
already owns elsewhere as a funding source, via `POST /api/v1/cards/link`.
Requires the user already hold at least one Dutch-Remit-issued card,
identity confirmation, and a $2.10 retrieval fee. **Security note:**
the CVV is read only in-memory for that one request and is never
written to any file, log, or database column — no column for it exists
on purpose (see `linked_cards` in `supabase/schema.sql`). The card
number itself is stored masked (last 4 digits only), never in full.
This is **not** a PCI-DSS-compliant card vault — a production system
handling real cardholder data at scale needs the card tokenized
client-side (a hosted field/iframe/SDK) so this backend never receives
the raw number at all. Treat this implementation as prototype-grade.

**Card-to-card transfers** (`card_to_card_transfer_screen.dart`) — move
money between two of your own cards, or to another Dutch Remit user's
card (found via `GET /api/v1/users/search`), via
`POST /api/v1/cards/transfer`. Recorded in the `card_transfers` ledger
table plus a matching pair of `transactions` rows. Neither Eversend
nor Klasha expose a real card-to-card transfer rail, so this is an
internal ledger entry — the same model as the "send to another Dutch
Remit user" wallet-balance transfer, not a real card-network movement.

## Endpoint map

| App feature | Route | Eversend call underneath |
|---|---|---|
| Wallet balances | `GET /api/v1/wallets`, `GET /api/v1/wallets/:currency` | `GET /wallets` |
| Global Transfer / Diaspora to Africa / Africa to Africa / Quick Transfer quote | `POST /api/v1/rates/payout-quotation` | `POST /payouts/quotation` |
| Wallet exchange quote (currency swap) | `POST /api/v1/rates/exchange-quotation` | `POST /exchanges/quotation` |
| Send to another Dutch Remit (Eversend) user — Invite tab | `POST /api/v1/rates/eversend-wallet-quotation` then `POST /api/v1/payouts/eversend` | `POST /payouts/quotation/eversend`, `POST /payouts/eversend` |
| Recipient tab — add/list/edit/delete beneficiary | `GET/POST/PATCH/DELETE /api/v1/beneficiaries` | `/beneficiaries` |
| Recipient tab — check if a phone/email is already on Eversend | `POST /api/v1/beneficiaries/check-eversend-account` | `POST /beneficiaries/accounts/eversend` |
| Deposit / Top Up (mobile money) | `POST /api/v1/collections/otp`, `POST /api/v1/collections/momo`, `GET /api/v1/collections/fees` | `/collections/*` |
| Withdrawal / Send — execute a payout | `POST /api/v1/payouts` | `POST /payouts` |
| Send Abroad hub — country/corridor pickers | `GET /api/v1/payouts/countries`, `GET /api/v1/corridors` | `GET /payouts/countries` + our confirmed corridor list |
| Delivery bank list for a country | `GET /api/v1/payouts/banks/:country` | `GET /payouts/banks/{country}` |
| Deposit / Withdraw — crypto method | `GET/POST /api/v1/crypto/addresses`, `GET /api/v1/crypto/transactions` | `/crypto/*` |
| Card tab — create virtual card, fund, withdraw | `POST /api/v1/cards`, `POST /api/v1/cards/user`, `POST /api/v1/cards/fund`, `POST /api/v1/cards/withdraw`, `GET /api/v1/cards/transactions` | `/cards/*` |
| Transaction history | `GET /api/v1/transactions` | `GET /transactions` (merged with Supabase's own log) |
| Eversend webhook (status updates) | `POST /api/v1/webhooks/eversend` | — receives events, writes to `webhook_events` and updates matching `transactions` rows |
| Legacy compatibility | `GET /Dutch Remit/v1/all-transactions` | Same shape the app already expects from `make_api_request.dart` |
| Login / signup — request code | `POST /api/v1/auth/otp/request` | Supabase Auth `signInWithOtp` — no password anywhere in the app; `purpose: 'signup'` creates the user, `purpose: 'login'` requires an existing one |
| Login / signup — verify code | `POST /api/v1/auth/otp/verify` | Supabase Auth `verifyOtp`; on signup also fills in name/address and generates a `dutch_remit_id` |
| Session restore | `GET /Dutch Remit/v3/user/:userId` (+ `dutch_remit` alias) | Looks up `profiles` by id |
| App info | `GET /Dutch Remit/app` | Static payload |
| Username availability / reservation | `GET /api/v1/auth/check-username`, `POST /api/v1/auth/set-username` | Replaces the old Socket.IO "username request" flow |
| Contacts | `GET /Dutch Remit/v3/all-contacts` | Reads `beneficiaries` |
| Business directory | `GET /Dutch Remit/v2/businesses-and-brands` | Reads `businesses` (seeded in schema.sql) |
| Pay a contact/business | `POST /Dutch Remit/v2/execute-transaction` | Records to `transactions`; does not itself move money on Eversend/Klasha — see the route's comments |
| Available cards (issued via this app) | `GET /Dutch Remit/v1/available-cards` | Reads `cards` |
| Card creation | `POST /api/v1/cards/user`, `POST /api/v1/cards` | Eversend's real Cards API — see "Cards" section below |
| Card management | `GET /api/v1/cards`, `GET /api/v1/cards/:cardId`, `POST /api/v1/cards/fund`, `/withdraw`, `/:cardId/freeze`, `/unfreeze`, `/terminate` | Eversend Cards API |
| Device sync | `POST /api/v1/devices` | Upserts `devices` |
| Notifications | `GET /api/v1/notifications`, `PATCH /api/v1/notifications/:id` | Reads/updates `notifications` |
| Klasha webhook | `POST /api/v1/webhooks/klasha` | Logs to `webhook_events`, syncs matching `transactions` — no signature verification yet, see above |
| **Unified send (any corridor):** used by Global Transfer / Diaspora to Africa / Africa to Africa / Quick Transfer / Withdrawal | `POST /api/v1/rates/quotation`, `POST /api/v1/payouts/send` | Auto-routes to Eversend or Klasha (`src/paymentRouter.js`) based on destination currency |
| Klasha bank list / account resolution / payout / virtual account | `GET /api/v1/klasha/banks/:currency`, `POST /api/v1/klasha/resolve-account`, `POST /api/v1/klasha/payout`, `POST /api/v1/klasha/virtual-account`, `GET /api/v1/klasha/virtual-account/:email`, `GET /api/v1/klasha/virtual-accounts/mine` | Confirmed real paths: `/wallet/merchant/bank/transfer/request/banks/:currency`, `/wallet/merchant/{businessId}/bank/transfer/v2/request` (3DES-encrypted), `/wallet/virtual/v3/business/create/account` (3DES-encrypted, NGN/GHS only). Virtual-account creation charges $0.50 first / $1.50 each additional (see PRICING.md) and, once created, a payout to that currency automatically routes Eversend wallet → virtual account → final Klasha payout (`paymentRouter.js`'s `VIRTUAL_ACCOUNT_CURRENCIES` two-hop flow — see "Virtual Accounts" home-screen entry) |
| Card linking ("Add a Card") | `POST /api/v1/cards/link` | Not an Eversend/Klasha call — an internal record in `linked_cards`, see "Cards" section above |
| Card-to-card transfer | `POST /api/v1/cards/transfer`, `GET /api/v1/cards/mine` | Internal ledger (`card_transfers`), see "Cards" section above |
| User directory search (for Send, card transfers) | `GET /api/v1/users/search?q=`, `POST /api/v1/users/verify` | Reads `profiles` — search by name/username, or verify a specific user exists by email/`dutch_remit_id` before saving them as a contact |

Every user-scoped route expects `Authorization: <token>` (also accepts
the `Bearer <token>` form) — the same header shape the Flutter app's
existing `getData`/`sendData` helpers already send. Two token types
work automatically:

- **Today:** the app's existing custom `authorization_token` from its
  current login flow. The backend hashes it, maps it to a stable
  `profiles.id` on first use via `legacy_sessions`, and reuses that
  mapping on every request after — so real per-user tracking in
  Supabase (transactions, beneficiaries, cards) works immediately,
  with no auth migration required to go live.
- **Later:** a real Supabase Auth session token, once/if the app
  migrates to Supabase Auth — resolved the proper way via
  `supabase.auth.getUser()`. Both paths land on the same
  `profiles.id`, so nothing else in the backend needs to change when
  that migration happens.

See `src/middleware/requireAppUser.js` for exactly how this works.

## Confirmed corridors — the real, current total

**Not 130+ countries.** This is the honest total across both
providers, confirmed against each one's own current API docs (not
secondary sources):

- **Eversend — 10 African payout corridors:** Cameroon, Ghana,
  Côte d'Ivoire, Kenya, Nigeria, Rwanda, Tanzania, Zambia, Senegal,
  Uganda. Sending side: Austria, Belgium, Bulgaria, Croatia, Cyprus,
  Estonia, Finland, France, Germany, Greece, Ireland, Italy, Latvia,
  Lithuania, Luxembourg, Malta, Portugal, Slovakia, Slovenia, Spain,
  plus the UK and US via GBP/USD wallets.
- **Klasha — 4 payout currencies:** NGN, ZAR, GHS (beta), KES (beta) —
  confirmed directly from developers.klasha.com/transfers/payout as
  of this pass. In practice this only adds **South Africa** as a
  genuinely new corridor on top of Eversend's list above, since
  Nigeria, Ghana and Kenya are already covered by Eversend and
  `resolveProvider()` prefers Eversend when both could serve a
  currency.
- **Total: 11 real payout destinations**, not 130+. An earlier pass
  at this backend stated a wider Klasha currency list (RWF, UGX, MWK,
  MZN, SLL, CDF, XOF, XAF, TZS, ZMW, CNY) sourced from indirect
  references rather than Klasha's own docs — that list was wrong and
  has been removed. If Klasha genuinely supports more corridors than
  their public payout page currently shows, ask them directly and
  I'll add the confirmed endpoint the same way NGN/ZAR/GHS/KES were
  added.
- Klasha's payout request needs a real **bank account number + bank
  code** (`GET /api/v1/klasha/banks/:currency` first) — it is bank-rail
  only per their docs, not a phone-number mobile-money flow the way
  Eversend's momo corridors are. `mobile_money_withdrawal_screen.dart`
  currently only collects a phone number, so a withdrawal that routes
  to Klasha (effectively: South Africa) will correctly return a clear
  "need a bank account + code" error rather than silently failing —
  but that screen doesn't have the UI for it yet. Same caveat applies
  to any Global Transfer wiring done later for a Klasha-routed
  currency.
- **Cameroon mobile-money beneficiaries (Eversend):** the documented
  beneficiary endpoint only *lists* NG/KE/UG, but Eversend confirmed
  other live momo corridors (Cameroon included) work the same way —
  pass `country: "CM"`, `isMomo: true`, and the recipient's phone in
  international format. `src/corridors.js` encodes exactly this, and
  `beneficiaries.js` validates against it before calling Eversend.
- **Klasha virtual accounts** are NGN/GHS only (confirmed from
  developers.klasha.com/bank-account-collection/virtual-account-creation) —
  `routes/klasha.js` rejects any other currency before calling Klasha.
- Eversend card endpoints (`/cards`, `/cards/user`, `/cards/fund`,
  `/cards/withdraw`) are confirmed directly from their docs — see
  "Cards" below.

## Setup (local)

```bash
cd Backend
npm install
cp .env.example .env   # a real, filled-in .env is already included for you — see below
npm run dev
```

A working `.env` with your Eversend and Supabase credentials has
already been created in this folder. **`.env` is git-ignored on
purpose — never commit it.**

## Deploy — 3 steps

1. **Adjust the backend proxy config.**
   - Confirm `.env` has your real `EVERSEND_CLIENT_ID` / `EVERSEND_CLIENT_SECRET`
     (already filled in) and `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`
     (already filled in).
   - Set `ALLOWED_ORIGIN` to your frontend's domain — already set to
     `https://dutchremit.dubiabank.com`. Add more origins comma-separated
     if you also test from `localhost`.
   - Run `supabase/schema.sql` once against your Supabase project
     (Supabase dashboard → SQL Editor → paste → Run).

2. **Host it on a live URL.**
   - Push this `Backend/` folder to its own GitHub repo (or a
     subdirectory of your existing one).
   - On Render: New → Web Service → connect the repo → it will pick up
     `render.yaml` automatically (or set build command `npm install`
     and start command `npm start` manually) → add the `sync: false`
     env vars in the Render dashboard (paste in the same values from
     `.env`) → Deploy. You'll get a URL like
     `https://dutch-remit-backend.onrender.com`.
   - (Any other Node host — Railway, Fly.io, a VPS — works the same
     way; `Procfile` is included for Heroku-style platforms too.)
   - In the Eversend dashboard, add
     `https://<your-backend-url>/api/v1/webhooks/eversend` as your
     webhook URL, copy the webhook secret it gives you into
     `EVERSEND_WEBHOOK_SECRET` on your host, and redeploy.

3. **Point the app at it.**
   - In the Flutter app, update `lib/resources/api_constants.dart`'s
     `baseUrl` to your new backend URL. The legacy `/Dutch Remit/v1/...`
     calls keep working immediately; migrate individual screens to the
     `/api/v1/...` routes above as you touch them.

## Security notes

## Klasha 502s from a hosted deployment (Railway, Render, etc.) — read this first

If Klasha calls work locally but return `502 Bad Gateway` only from a
hosted deployment, with identical code and no local errors — this is
almost always **IP whitelisting**, not a code bug. Diagnose it in one
call:

```
GET https://<your-backend-url>/diagnostics/klasha
```

This makes a real, live call to Klasha's NGN bank-list endpoint and
reports back:
- Whether `OUTBOUND_PROXY_URL` is configured at all
- The real error Klasha returned, if it failed
- Whether that error is a properly normalized message (confirms the
  deployed code is current) or the raw axios text like `"Request
  failed with status code 502"` (confirms the deployed code is
  **stale** — redeploy before debugging further, this exact class of
  bug has happened more than once this session)

**Why this happens:** most cloud hosts (Railway included) don't give
you a fixed outbound IP on their standard plans — your server's
outbound address can change between deploys or even between requests.
If Klasha's merchant account is configured to only accept requests
from a specific whitelisted IP (very common for financial APIs, and
the most likely explanation given "works locally, fails only when
hosted" with zero code differences), every request from a hosted
deployment will get rejected by Klasha's own infrastructure — which
can surface as a 502 from Klasha's own upstream, not from anything in
this codebase.

**The fix — already built, just needs to be turned on:**
1. Get a static outbound IP proxy (e.g. [QuotaGuard Static
   IP](https://www.quotaguard.com/), a Railway/Render add-on, or any
   HTTP(S) proxy service that gives you one fixed IP).
2. Set `OUTBOUND_PROXY_URL` on your host to that proxy's connection
   string (format: `http://user:pass@proxy-host:port`).
3. Give that exact IP to Klasha to whitelist on your merchant account
   (ask their support team, or check your merchant dashboard for a
   whitelisting setting).
4. Redeploy. Every Klasha call already routes through
   `makeProxyAgent()` (`src/klashaClient.js`) automatically once this
   one env var is set — no other code changes needed.

`src/klashaClient.js` builds a **fresh** proxy agent per request
rather than reusing one for the life of the process — a real, earlier
bug on this exact deployment: a single long-lived agent's pooled
socket goes stale after the container's been up a while, and every
call through it starts 502ing even with correct credentials and a
correctly-whitelisted IP. If you're still seeing intermittent 502s
*with* the proxy configured, confirm this fix is actually deployed
(the `/diagnostics/klasha` endpoint above reports the client version)
before assuming it's a new bug.

- The credentials in this message were shared in plaintext chat — treat
  them as already-exposed. Once you've confirmed the backend works,
  rotate the Eversend client secret and the Supabase service_role key
  from their respective dashboards, and update `.env` (and your host's
  env vars) with the new values.
- Never ship `SUPABASE_SERVICE_ROLE_KEY` or `EVERSEND_CLIENT_SECRET` to
  the Flutter app or any client-side code — only `SUPABASE_URL` and
  `SUPABASE_ANON_KEY` are safe there, for Supabase Auth itself.

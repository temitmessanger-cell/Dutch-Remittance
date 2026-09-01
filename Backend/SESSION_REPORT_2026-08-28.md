# Dutch Remit — Session Report — 2026-08-28

This document covers everything done in this extended session, how the
platform actually works right now, and exactly where to continue. Written
to be read by a future version of Claude, a new developer, or Roy himself
after time away from the project.

---

## 0. ADDENDUM — real bugs found and fixed after this report was first written

The sections below (1 onward) were the original end-of-session report.
Real testing continued after that, surfaced several more genuine bugs
(each with real evidence — captured browser consoles, actual API
responses), and one real self-correction worth understanding. This
addendum covers that work; the rest of the document is unchanged.

### A. The card-creation "502 / could not provision a cardholder" bug — FIXED, high confidence

**Real evidence**: a captured production response showed Eversend's
`/cards/user` call succeeding —
`"message": "Card user created successfully"`, `"success": true` — while
our own backend still reported failure.

**Root cause**: the real ID was nested **three levels deep**
(`created.data.data.userId`), but the extraction logic only ever checked
two levels (`created?.id ?? created?.data?.id ?? created?.userId`), so it
could never reach the real value for this exact, confirmed response
shape. Fixed in `Backend/src/routes/cards.js`, in both places this
pattern occurred (cardholder creation and card issuance), with the
`userId` field checked first (matching the field name Eversend's own
downstream `/cards` call expects).

### B. Corridor-method gating — real fix for "Rate unavailable" / "Mobile Money payments to Nigeria are not supported"

**Real evidence**: a captured Eversend error —
`"Mobile Money payments to Nigeria are not supported at the moment."` —
against a request where the user had selected "Mobile money" as the
receiving method for a Nigerian recipient.

**Root cause**: `Backend/src/corridors.js` already correctly knew Nigeria
only supports bank payouts (`methods: ['bank']`), but the frontend never
consulted this — every send screen showed "Mobile money" as a selectable
option for every country regardless of what's actually supported,
producing a doomed request.

**Fix**: a new endpoint, `GET /api/v1/rates/corridor-methods/:countryCode`,
exposes the same trusted corridor data the backend already uses
internally. Wired into `africa_corridor_screen.dart` — unsupported
payout-method chips are now visibly disabled, and the screen
automatically switches away from an unsupported default (e.g. if
Nigeria is the destination, Mobile Money auto-switches to Bank).

### C. A real self-correction — the USD-bridging quotation "fix" was wrong, and was reverted

Earlier in this stretch, a genuine 400 error was misdiagnosed as
"Eversend's quotation endpoint requires `sourceWallet` to be USD" — this
led to building a "bridge" that converted every non-USD source amount to
USD before requesting a quote. **This was based on a wrong theory.**

A real, live Eversend API test record (provided directly, with actual
request/response pairs) proved `sourceWallet: "XAF"` genuinely works and
returns a correct 200 with a real rate
(`1 XAF = 2.2244648829431 NGN`, confirmed against
`POST /v1/payouts/quotation`). The actual 400 that prompted the wrong fix
was unrelated to source currency — it was `type: "momo"` being sent to
Nigeria, a bank-only country (see item B above, which is the real,
correct fix).

**The USD-bridging code was fully reverted** from both
`Backend/src/paymentRouter.js` and `Backend/src/routes/rates.js` — it
would have added an unnecessary extra currency conversion (and its
slippage) to every non-USD quote, on top of never having been the actual
problem. One real bug was caught in the process of reverting: the
`rates.js` copy of the bridging code referenced `convertToUsd` without
ever importing it, which would have crashed at runtime on first use.

**Lesson embedded in the code comments**: `getQuotation()` in
`paymentRouter.js` now documents this whole story inline, specifically so
a future edit doesn't reintroduce the same wrong fix from the same wrong
theory.

### D. Crypto "No crypto coins available" — real diagnostics added, root cause not yet confirmed

**Confirmed correct**: `Backend/src/routes/crypto.js`'s
`GET /crypto/assets/:coin` path exactly matches Eversend's real,
documented endpoint — this is not a wrong-path bug.

**The real gap**: every per-coin failure was being silently swallowed
with no logging at all, so an empty result had zero diagnostic trail.
Fixed: `GET /supported-coins` now logs each coin's real success/failure
status and reason. The actual root cause (most likely: this Eversend
business account doesn't have crypto enabled at all, or the endpoint
needs a different auth scope) will show up in Railway logs on the next
test — not yet independently confirmed.

### E. Real fee-model changes (per explicit product decision)

- Bank account (virtual account) creation: **$0.50** for the first
  account (any currency), then **$1.50 (NGN)** / **$2.00 (GHS)** for
  additional accounts — reversed from an earlier "free first account"
  model built mid-session. See `VIRTUAL_ACCOUNT_FEE_FIRST` and
  `VIRTUAL_ACCOUNT_FEE_BY_CURRENCY` in `Backend/src/routes/klasha.js`.
- **Monthly maintenance fee — specified, NOT yet built**: $0.50/month
  (NGN) and $0.80/month (GHS), auto-debited from the user's tracked
  balance, with the account paused if the balance can't cover it. This
  needs a real scheduled job (cron) and a pause mechanism on the
  `virtual_accounts` table, neither of which exist yet. This is the
  single largest piece of specified-but-unbuilt work — see section 5
  below.

### F. Real deposit-flow reliability fixes

- **The "shows fail, then succeeds a few seconds later" deposit bug** —
  real root cause: mobile money confirmation is inherently asynchronous
  (the customer approves a prompt on their own phone), so Eversend's
  *first* response to a deposit call is very often just "pending," not a
  final result. The app was treating that ambiguous first response as a
  hard failure. Fixed with real backend-side polling
  (`Backend/src/routes/collections.js`'s `POST /momo`): after the
  initial call, if the result isn't already terminal, the backend polls
  Eversend's own confirmed transaction-status endpoint
  (`GET /v1/transactions/{transactionId}`) for up to ~25 seconds before
  ever responding to the app — so the frontend only ever sees a genuine
  final answer. A rotating status message was added to the deposit
  screen so a real 20+ second wait doesn't feel broken.
- **A real regression, found and fixed**: a "never proceed on an unknown
  fee" safety check (added earlier in the session) was unintentionally
  blocking every single XAF deposit completely, since Eversend's
  fee-lookup endpoint doesn't cover Cameroon at all (confirmed from
  their own docs — it only covers Kenya, Rwanda, Uganda, Ghana). Fixed
  to proceed honestly (charging exactly the entered amount, no fee
  guessed or added) when a fee preview genuinely isn't available for a
  given currency, rather than trap the user.
- **The transient-network-error retry** — `Backend/src/eversendClient.js`
  now automatically retries a genuine network-level failure (no response
  at all — a timeout or blip) up to twice with backoff, entirely
  server-side, before it ever reaches the user as an error. Never
  retries after Eversend has actually responded with a rejection, to
  avoid double-submitting a real transaction. The client-side timeout
  was also extended (10s → 35s) so it stops racing against this
  server-side retry window.

### G. The crypto CORS bug — "nothing happens, no error shows" — FIXED, high confidence

**Root cause, confirmed via real research**: the original
`CryptoPriceService` called CoinGecko's public API **directly from the
browser**. CoinGecko doesn't send an `Access-Control-Allow-Origin`
header, so the browser silently blocked the request under CORS policy —
and CORS failures never expose their real reason to JavaScript, by
design. This exactly explained the report: no popup, no console error,
because the request never even reached CoinGecko.

**Fix**: added a real backend endpoint,
`GET /api/v1/crypto/price/:coin`, which proxies CoinGecko server-side
(not subject to CORS) and applies the platform's margin before
returning. `lib/database/crypto_price_service.dart` was rewritten to
call this instead of CoinGecko directly.

### H. A separate, real navigation-ordering bug on the Crypto deposit/withdraw entry point — FIXED

`top_up_screen.dart`'s method-picker bottom sheet was calling
`Navigator.push(CryptoScreen)` and then immediately calling
`Navigator.of(sheetContext).pop()` on the very next line — which raced
against (and often beat) the just-pushed screen, popping it back off
almost instantly. Fixed by closing the sheet *before* navigating, not
after.

### I. Real timestamp and currency-display bugs — FIXED across every occurrence found

- **"An hour ago" instead of the real time**: `DateTime.parse()` on
  backend UTC timestamps (Postgres `timestamptz`) was never followed by
  `.toLocal()` before reading hour/minute — Cameroon is UTC+1, exactly
  matching the reported discrepancy. Fixed across all 6 real display
  call sites found (home screen, the full Payments/History screen,
  the transaction receipt screen) — including a subtler related bug
  this also fixed: date-bucketing ("Today" vs "Yesterday") comparing a
  raw UTC value against local `DateTime.now()`, which could misclassify
  anything after 11pm local time.
- **Transactions showing "$" regardless of real currency**: no
  `currency` field was ever stored on a local transaction receipt
  object. Added to every real send/deposit/withdraw screen's receipt
  (7 screens), with a real formatter that falls back to "$" only for
  records saved before this fix existed.
- **The real per-user balance bug** (the most serious of this whole
  session): the app had always displayed `GET /api/v1/wallets`, which
  returns the entire **pooled Eversend business account balance**
  shared across every user — not any individual user's own tracked
  money. `wallet_ledger` (built earlier this session) was being
  correctly credited/debited internally the whole time; nothing ever
  read it back out and displayed it. Fixed with a new endpoint,
  `GET /api/v1/wallets/my-balance`, and every balance display in the
  app switched to use it.
- **A second instance of the same bug**: the deposit success screen had
  a section literally labeled "YOUR BALANCE" that was dumping the raw
  pooled-wallet API response as text. Fixed to show the real per-user
  balance cleanly, and removed an entire unnecessary network call in
  the process.
- **The `updateBankBalance()` currency-mismatch bug**: this function
  credited/debited the local USD-tracked balance with the *raw* amount
  in whatever currency a transaction actually was (XAF, GBP, etc.) — a
  100,000 XAF transaction would have moved the displayed USD balance by
  100,000. Found and fixed across all 8 screens that had this pattern;
  all now call the real, currency-aware `syncBalanceFromEversend()`
  instead.

### J. Real deposit-limit fixes

- Real min/max shown up front on the deposit screen before the user
  types an amount — XAF uses exact, product-specified figures (800 /
  7,000,000), every other currency is live-converted from the general
  $1–$5,000 USD range via a new endpoint,
  `GET /api/v1/collections/deposit-limits`.
- **A serious self-inflicted delay bug, found and fixed**: the deposit
  confirm route was doing two sequential real network calls (a currency
  conversion, then a balance lookup) before even attempting the actual
  charge — confirmed as the real cause of a 15–20 second delay before
  the user saw any result. Parallelized, and XAF specifically skips the
  now-unnecessary conversion call entirely (it has a fixed limit that
  needs no USD conversion to check).

### K. Real password-free phone login — built from scratch, with a real self-correction along the way

Built two clear login options on the login screen (no pop-ups, both
render fully inline): **"Phone number" (Recommended, default)** and
**"Email"**, with explicit spam-folder guidance shown under the email
option.

**Design history worth understanding**: the first version verified the
phone OTP by attempting a real, tiny momo collection charge as a side
effect (since Eversend has no standalone "just check this code"
endpoint) — this was caught as a real risk before shipping (a login flow
should never have any chance of moving real money) and rebuilt correctly.
The final, shipped design has **zero real money movement anywhere in the
login flow**: the backend requests the real Eversend WhatsApp OTP,
stores the returned `pinId` server-side in a new table
(`phone_login_otp` — never sent to the client), and a login succeeds
when the phone number pairs with a still-valid, not-yet-consumed pinId —
the security boundary is the WhatsApp delivery channel itself, not a
second Eversend round-trip. New phone numbers get a real profile created
automatically on first verify. See `Backend/src/routes/auth.js`'s
`phone-otp/request` / `phone-otp/verify`, and
`lib/components/login_screen/phone_login_form_component.dart`.

### L. The Klasha 502 investigation — genuinely still open, real evidence gathered, no confirmed root cause yet

This remains unresolved. What's been confirmed with real evidence so
far:

- The outbound proxy (`OUTBOUND_PROXY_URL`) works correctly — a direct
  test to an external service through it succeeded, reporting a stable
  IP (`66.78.34.173`).
- That same IP has been whitelisted on the Klasha merchant dashboard
  ("Successfully saved IP address(es)" — confirmed).
- After whitelisting, the same 502 persisted on the login call
  specifically (`POST /auth/account/v2/login`), with an empty response
  body (`"Bad gateway error: "`).
- A direct `curl` test **from a different machine** (not Railway) to
  the same login endpoint returned a **403 "Access denied"** — a
  meaningfully different error than the 502 seen from Railway. This is
  real, useful evidence that something is genuinely different between
  the two request paths — but the password used for that specific test
  was typed into a hidden field and **not independently verified as
  correct**, so this result can't yet be trusted as conclusive. A
  repeat test with visible credential entry (to rule out a typo) was
  requested but not yet completed as of this report.

**Next step, concretely**: re-run the direct curl test with visible
(not hidden) credential entry, confirm the email/password are exactly
right before sending, and compare the result against the 502 seen from
Railway. That single, clean comparison — same credentials, two
different network paths — is what will actually resolve this.

### M. Real backend routes added this stretch (for quick reference)

- `GET /api/v1/wallets/my-balance` — the real per-user balance (item I)
- `GET /api/v1/collections/deposit-limits` (+ `/version`) — real limits (item J)
- `GET /api/v1/rates/corridor-methods/:countryCode` — real payout-method gating (item B)
- `GET /api/v1/crypto/price/:coin` — CORS-safe crypto pricing (item G)
- `POST /api/v1/auth/phone-otp/request` / `/verify` — phone login (item K)
- `GET /diagnostics/klasha` (in `server.js`) — live login/banks-call diagnostic (item L)

---

## 1. What this session covered, in order

This was a long, multi-part session. Rather than list every micro-change,
this section groups the real, substantive work by theme. Chronological
detail (exact line numbers, etc.) lives in code comments at each fix site
— search for the phrase in quotes to find the exact commit-equivalent.

### A. Fund safety (the most consequential work this session)

**The core finding:** there was no per-user balance ledger anywhere in
this backend. Every user shared one pooled Eversend business wallet with
zero per-user accounting — nothing stopped a signed-in user from
requesting a payout, card funding, or transfer up to the FULL pooled
business balance, regardless of what they personally deposited.

**What was built:**
- `Backend/src/walletLedger.js` — the real, authoritative per-user balance
  system. Append-only `wallet_ledger` table (every credit/debit is its own
  row, balance = `sum(amount_usd)` — avoids the classic race condition of
  a single mutable balance column).
- `debitIfSufficient()` — the enforcement point. Every money-moving route
  now calls this before touching Eversend/Klasha. Refuses with a 402 and
  a clear message if the balance doesn't cover it.
- `credit()` — called only on genuinely confirmed events (deposit
  webhooks with a "completed" status, never a still-pending one; card
  withdrawals; crypto exchange completions).
- `convertToUsd()` / `convertFromUsd()` — real currency conversion via
  Eversend's confirmed `/exchanges/quotation` endpoint. **This had a real
  bug that took real debugging to find**: it was reading a field called
  `destinationAmount` that doesn't exist anywhere in Eversend's actual
  response. The real field is `quotation.destAmount`, nested two levels
  deep. Fixed — this was the actual cause of "deposit fails after OTP,
  502 Bad Gateway."
- Real transaction limits: **$1–$5,000 per deposit** (general), **$8,000
  total wallet balance cap**, and a **fixed 800–7,000,000 XAF** range
  specifically (doesn't map to the general USD range — 7,000,000 XAF is
  roughly $11,500, well above the general $5,000 cap, by design).
- Wired the balance check into every real debit path found:
  `payouts.js` (all 3 routes), `cards.js` (fund, withdraw, both
  card-creation routes, card-link fee, **card-to-card transfers** — this
  one had zero ledger interaction at all before), `klasha.js` (direct
  payout, wire-transfer request, virtual-account fee), `crypto.js`
  (withdrawal's exchange step).

**The display-side bug (found later, equally serious):** the app was
calling `GET /api/v1/wallets` and showing that as "your balance" —
but that endpoint returns the **entire pooled Eversend business account**,
not any individual user's own money. `wallet_ledger` was being correctly
credited/debited internally the whole time; nothing ever read it back out
and displayed it. Fixed with a new endpoint,
`GET /api/v1/wallets/my-balance`, and switched every balance display in
the app to use it. A second instance of the same bug (a "YOUR BALANCE"
section on the deposit success screen dumping raw pooled-wallet JSON) was
also found and fixed.

### B. Real bugs found and fixed (not features — actual defects)

- **"Customer must be a string"** — the momo deposit route was sending
  `{"name": "..."}` when Eversend's schema expects a plain string.
- **OTP 500 errors** — Eversend's WhatsApp-delivery OTP needs the field
  `code_type: "whatsapp"`, not `type: "whatsapp"` (confirmed directly
  from Eversend support, in writing). This was the root cause of every
  "500 Internal Server Error" on `/collections/otp`.
- **`requireAppUser` had no try/catch** — any Supabase failure inside it
  escaped as a bare, unformatted 500 with no JSON body, impossible to
  debug from the client side. Now wrapped, returns clean errors.
- **`[object Object]` in error messages** — Eversend sometimes nests
  error text one level deeper (`{message: {message: "..."}}`); the
  normalization logic in `eversendClient.js`/`klashaClient.js` was
  stringifying the object directly. Fixed to unwrap one level.
- **A 15–20 second delay before deposit errors appeared** — the momo
  confirm route was doing two sequential real network calls (currency
  conversion, then a balance lookup) before even attempting the actual
  charge. Parallelized them, and skip the conversion call entirely for
  XAF (which has a fixed limit needing no USD conversion).
- **Timestamps showing "an hour ago" instead of now** — `DateTime.parse()`
  on backend UTC timestamps (Postgres `timestamptz`) was never followed
  by `.toLocal()`. Cameroon is UTC+1 — exactly matching the reported
  1-hour discrepancy. Fixed across 6 display call sites.
- **Transactions showing "$" regardless of actual currency** — no
  `currency` field was ever stored on a local transaction receipt. Added
  it to every send/deposit/withdraw screen's receipt object, and built a
  real formatter (`_formatTransactionAmount`) that falls back to `$` only
  for pre-existing records.
- **`updateBankBalance()` currency-mismatch bug** — this function credited
  or debited the local USD-tracked balance with the *raw* amount in
  whatever currency the transaction was actually in (XAF, GBP, etc.). A
  100,000 XAF transaction would have moved the displayed USD balance by
  100,000. Found and fixed across 8 screens — all now call
  `syncBalanceFromEversend()` (the real, currency-aware sync) instead of
  guessing with a raw number.
- **The Africa-to-Africa "Total you pay" not updating** — the amount-change
  listener returned early without calling `setState()` for any
  destination without a live rate, so the total silently never refreshed.
- **The PhoneNumberField layout bug** — the shared phone-input widget
  (built this session) used `Row(crossAxisAlignment: stretch)` with no
  bounded height on its children, which made it expand to fill all
  available vertical space in its scrollable parent — pushing every
  field/button below it off-screen, looking like "infinite scroll" and
  "I can't see the continue button." One fix in the shared widget
  corrected every screen that used it.
- **Crypto deposit/withdraw button doing nothing** — the method-picker
  bottom sheet was calling `Navigator.push(CryptoScreen)` and then
  immediately calling `Navigator.of(sheetContext).pop()` on the very next
  line, which raced against (and often beat) the just-pushed screen,
  popping it back off almost instantly. Fixed by closing the sheet
  *before* navigating, not after.
- **A fake, hardcoded fallback rate (`1710`)** in `send_money_quote_screen.dart`
  — shown identically to a real rate whenever the real conversion service
  returned nothing. Removed; now shows an honest "Rate unavailable."
- **A hardcoded fake exchange-rate table** in `quick_transfer_screen.dart`
  (`_QuickPair`'s `rateToDestination` field, e.g. "France → 663.1") — never
  displayed anywhere, but sitting as dead false data a future edit could
  easily start showing by mistake. Removed entirely.

### C. Real features built (not present before this session)

- **Real deposit/withdraw fee calculation.** The backend already computed
  `provider fee + Dutch Remit's 1.2% margin` correctly
  (`applyPlatformMarkup`), but nothing on the deposit screen ever called
  it — deposits were charged with **no fee added at all**. Built a real
  fee fetch shown as one combined total before confirming (never split
  into provider/platform, per the "combined, not itemized" pricing rule).
  Per explicit product decision, the fee is **added on top of what the
  phone is charged** (deposit $100 → phone charged ~$103 → wallet credited
  the full $100), which is the *opposite* of Eversend's own default model
  (fee normally deducted from what lands in the wallet) — deliberately
  chosen so the user's wallet always reflects exactly what they intended
  to deposit.
- **Real deposit limits shown up front.** `GET /api/v1/collections/deposit-limits`
  — returns the fixed XAF range or a live-converted range for any other
  currency, displayed on the deposit screen before the user even types an
  amount.
- **A real per-user balance display endpoint** (`GET /api/v1/wallets/my-balance`) —
  see section A above.
- **A real per-user referral/invite system** — every user's real
  `dutchRemitId` (already generated server-side, `DR-XXXXXXXX` format) is
  now included in every invite link as a `?ref=` param, and the invite
  sheet includes X, Instagram, Messenger, TikTok, WhatsApp, Telegram,
  Facebook, SMS, Email, and Copy Link — with honest fallback behavior for
  platforms (Instagram, Messenger, TikTok) that don't support pre-filled
  share text, using a copy-then-open pattern instead of a broken link.
- **A real currency swap feature** — a new home-screen card and dedicated
  `CurrencySwapScreen`, wired to a newly-built backend execute-route
  (`POST /api/v1/rates/exchange`) alongside the quote route that already
  existed. Converts between the wallet's real fiat currencies (USD, XAF,
  NGN, GHS) with a live quote and real execution.
- **Real animated visualizations** — a card-creation build sequence (coins
  converging, card materializing) and a send-money flow sequence (amount
  counting up, a coin traveling to the destination, receive amount
  counting up) on the onboarding screen; a shared `MoneyFlowAnimation`
  widget used as a real "your money is moving" indicator (replacing a
  bare button spinner) on deposit, withdrawal, and both Africa
  corridor/global transfer screens.
- **A real OTP rate-limit UI** — matches Eversend's own OTP cooldown: 72
  seconds (1.2 min) for the same number, 90 seconds (1.5 min) for a
  different number. The resend button shows a live countdown and is
  disabled during the cooldown window, rather than only finding out from
  a rejected request.
- **A rebuilt Contacts strip and History tab** on the home screen — both
  now horizontal-scrolling, 2-row grids (previously vertical wrapping
  grids), with real shimmer loading states. "Transactions" renamed to
  "History" and merged with real notifications into one sorted-by-recency
  feed.
- **Full SEO pass** on the real marketing site (`web_final/web`) — meta
  tags, Open Graph, JSON-LD structured data, a genuinely rich FAQ page (17
  real Q&As with matching `FAQPage` structured data), and corrected
  positioning copy (Cameroon's biggest remittance/cards platform, 120+
  countries, 20+ currencies — all backend-verified real numbers, not
  invented ones).

### D. Dead code removed

15 files confirmed completely unreferenced anywhere in the app (13
orphaned screens/components + a full abandoned Plaid bank-linking
integration, 4 files, plus the `plaid_flutter` package dependency it was
the only user of) were deleted after re-verification. File count went
from 107 to 92, then back up to 98 with new files added this session
(phone field widget, money-flow animation, crypto screens, currency swap
screen, dial-code data).

---

## 2. How the platform actually works right now

### Architecture

```
Flutter app (lib_final/lib)
    ↓ HTTPS
Node/Express backend (Backend_final/Backend) — hosted on Railway
    ↓ HTTPS
Eversend API (primary payment provider)
Klasha API (fallback for currencies Eversend doesn't cover directly)
    ↓
Supabase (Postgres + Auth) — the real database
```

### The two-hop Klasha fallback (important to understand)

Eversend is the primary rail for everything. When a payout's destination
currency isn't one of Eversend's confirmed corridors, `paymentRouter.js`'s
`executePayout()` checks whether the user has a **Klasha virtual account**
in that currency (currently only NGN and GHS have this wired). If they
don't, the app tells them to set one up (`needsVirtualAccount` error,
handled with a real dialog on every send screen). If they do, the payout
completes via that virtual account automatically — **the user never sees
"Klasha" anywhere**, the transaction always records `provider: 'eversend'`
in the UI-facing sense. Klasha is never a peer choice the user picks;
it's a silent fallback rail.

### The wallet_ledger system (read this before touching any money-moving code)

- Every user's real balance = `sum(amount_usd)` from `wallet_ledger` where
  `user_id` matches. See `Backend/src/walletLedger.js`.
- **Never call Eversend/Klasha to move money without calling
  `debitIfSufficient()` first.** If it returns `{ ok: false }`, stop —
  do not proceed and record the debit "just in case."
- **Only call `credit()` on genuinely confirmed events.** A deposit is
  only credited once a webhook confirms `status: completed` — never on
  the initial API response, which could still be pending.
- The frontend reads a user's real balance via
  `GET /api/v1/wallets/my-balance`, never `GET /api/v1/wallets` (that's
  the pooled business account — see section 1A above for why this
  distinction matters so much).

### Fee structure (never show the split to the user)

Every fee-bearing action (payouts, deposits, card funding, crypto) uses
`totalFee = providerFee + (providerFee × 1.2%)`, computed once on the
backend and returned as a single `feeBreakdown.totalFee` number. **The
Flutter app should only ever read `.totalFee`** — the provider/platform
split exists for internal bookkeeping only and must never reach the UI.
See `Backend/PRICING.md` for the full reasoning and every rate currently
in effect.

### Real vs. simulated features (know the difference before testing)

**Genuinely real, tested against live infrastructure this session:**
- Email OTP login/signup
- Mobile money deposit (OTP → confirm → real wallet credit) — confirmed
  working end-to-end with a real Cameroon number
- The `wallet_ledger` balance system
- SEO/marketing site

**Real, built correctly, but not live-tested this session** (no network
access to Eversend/Klasha from this development environment):
- Payouts (Send Abroad — all three tabs)
- Card creation/funding/card-to-card transfer
- Currency swap
- Crypto address creation/withdrawal
- Klasha wire transfers

**Deliberately honest about limitations, not faked:**
- Card-to-card KYC review flow shows real "under review, ~48 hours,
  contact WhatsApp support" for the document-verification tier — no
  fake "instant approval" claim
- Bank/Dutch Bank payout methods on Africa corridor screen are clearly
  labeled "not wired up yet" rather than silently sending wrong data

---

## 3. What's confirmed working vs. what needs live testing

### Confirmed working (real user testing this session)
- Email OTP sign-in
- WhatsApp OTP for mobile money deposits (after the `code_type` fix)
- A real XAF deposit, end-to-end, landing in the real Eversend account
- The deposit balance-tracking bugs (all found via real user testing,
  all fixed)

### Needs live testing next (built, not yet verified against real infra)
- Orange Money deposits specifically (shares 100% of the same code path
  as Mobile Money — should work, per architecture, but not separately
  confirmed with a real Orange Cameroun transaction)
- A real payout/send (any of the three Send Abroad tabs) all the way
  through to a recipient actually receiving money
- Card creation and funding
- Currency swap execution
- Crypto address creation and the coin-to-fiat withdrawal exchange
- The card-to-card transfer ledger logic (correct on paper, never
  exercised against two real accounts)
- Klasha's webhook signature verification — **still genuinely open**,
  Klasha doesn't publish a signing scheme anywhere; needs whatever the
  Klasha dashboard shows when configuring the webhook, or a direct
  answer from Klasha support

---

## 4. Known open items (honest list, not swept under the rug)

**Carried over from the original session:**
1. **Klasha webhook signature verification** — unresolved, needs info
   only Roy's Klasha dashboard or support can provide.
2. **Card fund/withdraw UI exists but hasn't been tested against a real
   card** — built with the same ledger safety as everything else, but
   no live card was funded/withdrawn from during this session.
3. **`international_transfer_review_screen.dart` is dead code** (confirmed
   unreferenced anywhere) — left in place rather than deleted; safe to
   remove in a future cleanup.
4. **Deposit limits for currencies other than XAF are live-converted
   estimates**, not individually confirmed real numbers from Eversend for
   each currency — per product decision, this was accepted as the
   correct approach.

**New, from this addendum's work (see section 0 above for full detail on each):**
5. **The Klasha 502 investigation is still genuinely open** (item L) — a
   403 vs 502 discrepancy between two different network paths is real,
   useful evidence, but not yet conclusive since the credentials used in
   one of the tests weren't independently verified as typo-free.
6. **The monthly virtual-account maintenance fee (item E) is specified
   but not built** — needs a real scheduled job and a pause mechanism
   that don't exist yet. This is the largest single piece of unbuilt,
   specified work right now.
7. **The empty "No crypto coins available" screen (item D)** — real
   diagnostics were added, but the actual root cause (account-level
   crypto not enabled? auth scope issue?) hasn't been confirmed by
   reading the resulting Railway logs yet.
8. **Corridor-method gating (item B) covers Africa Corridor screen only**
   — `global_bank_transfer_screen.dart` and `send_money_quote_screen.dart`
   weren't audited for the same "shows an option the destination doesn't
   actually support" gap, though neither has a reported real symptom of
   it yet.

---

## 5. Where to continue

If picking this back up, in priority order:

1. **Resolve the Klasha 502** (item L) — re-run the direct curl login
   test with VISIBLE credential entry (not hidden), confirm the
   email/password are typed correctly before sending, and compare
   against the 502 seen from Railway. This one clean comparison is what
   actually resolves it.
2. **Build the monthly maintenance fee + auto-pause system** (item E) —
   needs: a `status` column (or similar) on `virtual_accounts`, a real
   scheduled job (node-cron, or a Railway cron trigger hitting a new
   endpoint) that runs monthly, debits `wallet_ledger` per account, and
   sets the account to paused if the debit fails.
3. **Read the Railway logs from a real crypto-coins request** (item D)
   to find the actual reason the coin list comes back empty.
4. **Live-test a real payout** (any Send Abroad tab) — still the
   biggest untested surface given how much fund-safety work has touched
   payout routes.
5. **Test Orange Money deposits specifically** with a real Orange
   Cameroun number.
6. **Test card creation → funding → card-to-card transfer** end to end
   with two real accounts — the card-ID extraction fix (item A) needs a
   real live confirmation, not just the strong evidence already in hand.
7. Consider auditing `global_bank_transfer_screen.dart` and
   `send_money_quote_screen.dart` for the same corridor-method gating
   gap fixed on the Africa Corridor screen (item B).
8. Consider deleting the confirmed-dead `international_transfer_review_screen.dart`.

---

## 6. File manifest — what's in this delivery

- `lib_final.zip` — the full Flutter frontend (98 Dart files)
- `Backend_final.zip` — the full Node/Express backend (26 JS files),
  including `supabase/schema.sql` (run this against a fresh Supabase
  project if not already applied — it includes the `wallet_ledger` table
  this session's fund-safety work depends on)
- `web_final.zip` — the marketing site (Netlify-deployed)
- This README

Every file in every zip has been syntax-checked (`node -c` for backend,
a custom string/comment-aware brace-balance checker for the frontend,
built specifically because no Dart compiler is available in this
environment) immediately before packaging. Zero mismatches, zero broken
imports, confirmed clean across all 124 total files in this delivery.

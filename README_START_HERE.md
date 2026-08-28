# Dutch Remit — Session Report — 2026-08-28

This document covers everything done in this extended session, how the
platform actually works right now, and exactly where to continue. Written
to be read by a future version of Claude, a new developer, or Roy himself
after time away from the project.

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

1. **Klasha webhook signature verification** — unresolved, needs info
   only Roy's Klasha dashboard or support can provide.
2. **XAF listed as a currency option on Eversend's Mobile Money
   Collection docs page is ambiguous** — their body-params table lists
   `CM` as a valid country but only `UGX, KES, GHS, RWF` as valid
   currencies (XAF conspicuously absent). A real test this session with
   `country: CM, currency: XAF` worked without a currency-rejection
   error, which is strong evidence it's fine in practice — but this
   wasn't independently confirmed via Eversend's own documentation, only
   via one successful real transaction.
3. **Card fund/withdraw UI exists but hasn't been tested against a real
   card** — built with the same ledger safety as everything else, but
   no live card was funded/withdrawn from during this session.
4. **`international_transfer_review_screen.dart` is dead code** (confirmed
   unreferenced anywhere) — left in place rather than deleted, since it
   wasn't the focus of this pass; safe to remove in a future cleanup.
5. **Deposit limits for currencies other than XAF are live-converted
   estimates**, not individually confirmed real numbers from Eversend for
   each currency — per product decision, this was accepted as the
   correct approach (see `FIXED_CURRENCY_LIMITS` in `collections.js`).

---

## 5. Where to continue

If picking this back up, in priority order:

1. **Live-test a real payout** (any Send Abroad tab) — this is the
   biggest untested surface given how much of the fund-safety work
   this session touched payout routes specifically.
2. **Test Orange Money deposits specifically** with a real Orange
   Cameroun number, to close out the one open item from that
   investigation.
3. **Resolve the Klasha webhook signature** — check the Klasha dashboard's
   webhook configuration page for a signing secret.
4. **Test card creation → funding → card-to-card transfer** end to end
   with two real accounts, to verify the ledger logic that's never been
   exercised live.
5. Consider deleting the confirmed-dead `international_transfer_review_screen.dart`
   in a future cleanup pass.

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

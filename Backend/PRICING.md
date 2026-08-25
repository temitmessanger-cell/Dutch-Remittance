# Dutch Remit — Pricing structure

How every fee/margin in this backend is actually computed, and where
in the code each one lives. The user never sees a "provider fee" and
"our fee" as two separate line items anywhere — every quote and
receipt shows one combined total. That's a deliberate rule, not an
oversight: see "Why combined, not itemized" below.

## 1. Payouts (Send Abroad, Withdrawal, Quick Transfer)

**Formula:** `totalFee = providerFee + (providerFee × 1.2%)`

Applied in `src/paymentRouter.js`, `applyPlatformMarkup()`. Whatever
Eversend/Klasha actually charges for a transfer, Dutch Remit adds a
1.2% margin on top of *that fee* (not on the principal amount being
sent). On a typical $2–$10 payout fee, that's roughly $0.02–$0.12 —
genuinely not noticeable to a user, but real revenue at volume.

Every quotation call (`POST /api/v1/rates/quotation`,
`/payout-quotation`) returns this via a `feeBreakdown` object:
```json
{ "providerFee": 2.00, "platformMarkupRate": 0.012, "platformMarkup": 0.02, "totalFee": 2.02 }
```
The Flutter app only ever reads `feeBreakdown.totalFee` — the
provider/platform split exists for our own bookkeeping, never shown
in the UI.

## 2. Deposits (mobile money collections)

**Formula:** same as payouts — `applyPlatformMarkup()` reused in
`src/routes/collections.js`'s `GET /fees` endpoint. Whatever Eversend
charges to collect a mobile-money deposit, add 1.2% on top.

## 3. Wallet-to-wallet currency exchange

**Formula:** a 0.5% spread baked into the converted amount, in
`src/routes/rates.js`, `applyExchangeMarkup()`.

This one works differently on purpose: an FX conversion quote
(`POST /api/v1/rates/exchange-quotation`) doesn't carry a separate
"fee" field the way a payout does — providers price conversions
purely through the rate. So the margin here is taken the same way
every remittance/FX product takes it: quote a rate slightly worse
than the provider's true rate, rather than adding a visible fee line.
0.5% is intentionally small — noticeable margin here (a bad rate)
is the single fastest way to lose trust and users to a competitor's
rate-comparison screenshot.

## 4. Card creation (`src/routes/cards.js`)

These are flat, disclosed fees — not hidden margin — because card
issuance is a discrete, opt-in purchase, not a rate a user is
comparing across providers:

| Fee | Amount | Where |
|---|---|---|
| Card creation, one-time | $3.50 | `CARD_FEE_ONE_TIME` |
| Card creation, monthly | $1.10/mo | `CARD_FEE_MONTHLY` |
| Proceed without KYC | +$1.50 | `KYC_SKIP_FEE` |

## Why combined, not itemized

Showing a user "Provider fee: $2.00 + Dutch Remit fee: $0.02" invites
the obvious next question — "why do you get a cut?" — for a number
too small to matter to them but that reveals the entire margin
structure to anyone paying attention (and to competitors). A single
"Fee: $2.02" is honest (it's the real, total cost — nothing hidden in
the rate elsewhere) without publishing the margin. Every screen that
shows a fee (`send_money_quote_screen.dart`, `africa_corridor_screen.dart`,
the deposit/withdrawal flows) was built or updated to only ever render
the combined total.

## Adjusting these numbers later

Every rate lives as a single named constant at the top of its file
(`PLATFORM_MARKUP_RATE` in `paymentRouter.js`, `EXCHANGE_MARKUP_RATE`
in `rates.js`, the `CARD_FEE_*`/`KYC_SKIP_FEE` constants in
`cards.js`) — change the number in one place, nothing else to hunt
down. If you want per-corridor margins (e.g. a slightly higher margin
on a corridor with thin competition, lower on one where a competitor
undercuts you), that's a straightforward extension of
`applyPlatformMarkup()` to take `destinationCurrency` into account —
not built yet, since no such requirement was specified.

## What this doesn't cover yet

- Klasha's payout flow doesn't expose a pre-send quotation endpoint at
  all (see the comment in `getQuotation()`) — its fee is confirmed
  only in the actual transfer response, so no markup is applied to a
  Klasha *quote* today; the transfer itself still succeeds. If Klasha
  adds a quotation endpoint later, wire it through
  `applyPlatformMarkup()` the same way.
- These numbers are unverified against live provider responses (this
  environment's network egress doesn't reach Eversend/Klasha — see
  Backend/README.md). Confirm the actual `fee` field name Eversend
  returns on a real `/payouts/quotation` call before relying on this
  in production; `applyPlatformMarkup()` currently guesses `fee` →
  `charge` → `totalFee` defensively and falls back to $0 provider fee
  (meaning $0 markup too) if none of those match.

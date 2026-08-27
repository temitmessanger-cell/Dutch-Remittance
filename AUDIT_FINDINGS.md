# Dutch Remit — Full Platform Audit

Session date: 2026-08-27. Scope: every file in lib_final/lib (107 Dart) and
Backend_final/Backend/src (25 JS), checking for dead code, fake/fabricated
data, and broken flows.

## Methodology
1. Automated scan for red-flag patterns (TODO/FIXME, hardcoded fake data,
   unused imports, orphaned files not referenced anywhere)
2. Flow-by-flow manual review: auth, deposit, withdraw, send abroad, cards,
   profile/settings, home dashboard
3. Cross-check every screen against the backend route it calls, confirming
   the route actually exists and does what the screen assumes

## Findings

### Dead code — confirmed unreferenced anywhere in the app
Cross-checked every screen/component class name against every import and
instantiation site in the codebase. These files are never imported, never
instantiated, and have zero live route into them:

1. `screens/link_bank_account_screen.dart` (`LinkBankAccountScreen`)
2. `screens/plaid_bank_transfer_screen.dart` (`PlaidBankTransferScreen`)
3. `screens/new_settings_screen.dart` (`NewSettingsScreen`)
4. `screens/send_money_tab_screen.dart` (`SendMoneyTabScreen`)
5. `screens/international_transfer_screen.dart` (`GlobalTransferTabContent`)
   — pre-existing dead code, not something this session caused: its one
   remaining live call site was `explore_product_screen.dart`'s
   "Importers & traders" persona, which routed here for lack of a better
   option before this session replaced it with the real
   `WireTransferRequestScreen`. `send_abroad_hub_screen.dart`'s actual
   "Global Transfer" tab has always used `GlobalBankTransferScreen`
   instead (a different, working screen) — this file was never the real
   Global Transfer flow.
6. `screens/all_contacts.dart` (`AllContactsScreen`)
7. `components/qr_code_scanner_screen/my_qr_screen.dart` (`MyQRCodeScreen`)
8. `components/qr_code_scanner_screen/post_successful_qr_scan.dart` (`PostSuccessfulQRScanScreen`)
9. `components/settings_screen/app_creator_info.dart` (`AppCreatorInfoScreen`)
10. `components/settings_screen/credits_screen.dart` (`CreditsScreen`)
11. `components/main_app_screen/loading_screen_component.dart` (`LoadingScreenComponent`)
12. `components/add_card_screen/card_processing_screen.dart` (`CardProcessingScreen`)

Also dead, in `utilities/`:
13. `utilities/hadwin_icons.dart` (`DutchRemitIcons`) — a custom icon font
    class (`HadWinIcons`), never referenced anywhere. If the font asset
    itself isn't declared in pubspec.yaml either, this is fully removable;
    if it is declared, at minimum the font asset is being shipped for
    nothing.

### Dead integration: Plaid (entire feature, not just individual screens)
`services/plaid_service.dart`, `resources/plaid_api_constants.dart`,
`screens/link_bank_account_screen.dart`, and `screens/plaid_bank_transfer_screen.dart`
(the latter two already listed as #1/#2 above) are a complete,
self-contained Plaid bank-linking integration with zero live references
from anywhere else in the app. This isn't a few stray screens — it's a
whole abandoned feature (external bank account linking via Plaid),
superseded by the real Eversend/Klasha virtual-account flow this session
worked on. The `plaid_flutter` package dependency (confirmed via package
import scan earlier this session) is only pulled in to support this dead
code — removing these files would let `plaid_flutter` be dropped from
pubspec.yaml too, trimming a real dependency the app doesn't use.

**Recommendation:** delete all 13 numbered files plus `services/plaid_service.dart`
and `resources/plaid_api_constants.dart` (15 files total). None are
referenced by any import, any instantiation, or any string-based routing.

### Backend capability with no frontend caller (gap, not dead code)
`POST /api/v1/cards/fund` and `POST /api/v1/cards/withdraw` (Backend/src/routes/cards.js)
are real, working routes against Eversend's confirmed Cards API — but no
screen anywhere in the app calls either one. A card can be created and
funded at creation time, but there's no way to top up an existing card's
balance again later, or pull money back out of a card into the wallet,
without going outside the app. This is the reverse of dead code: working
backend capability the frontend never surfaces. Worth a dedicated "Fund
this card" / "Withdraw from card" action on the card details screen.

### Fixed during audit: Gifts screen was faking money movement (real bug, not a gap)
`screens/gifts_screen.dart`'s `_confirmGift()` used `await Future.delayed(const
Duration(milliseconds: 900))` with **no backend call at all** — it decremented
the local wallet balance, wrote a fake success receipt, and showed "Gift
sent!" while the recipient never received anything and no money moved on
Eversend. This is a live, reachable screen (Gifts tab in Send Abroad hub),
not dead code, and directly contradicts the screen's own doc comment
("never a placeholder or invented name") and the pattern established
everywhere else in this codebase (every other send flow was already
audited this session and genuinely calls the real quote→payout pair).

Fixed: gifts now go through the same `POST /api/v1/rates/quotation` →
`POST /api/v1/payouts/send` pair as `africa_corridor_screen.dart`. This
required two supporting fixes since the screen previously had no way to
know where to send the money:
- The static `kGiftDestinationCountries` string list (13 country names,
  never wired to any state — no `onTap`, purely decorative chips) was
  replaced with a real, tappable selector built on `kAfricanCountries`,
  scoped to `isEversendCorridor: true` countries only.
- Sending is now blocked with a clear message if the recipient contact
  has no saved phone number, or if no destination country is chosen —
  rather than silently sending to nowhere.

### Fixed during audit: Notifications tab was permanently empty
Confirmed the gap already flagged in the README earlier this session:
`GET/PATCH /api/v1/notifications` only ever `select`/`update` the
`notifications` table — nothing anywhere ever `insert`s a row, so the
Notifications upper nav built this session would show "No notifications
yet" forever in production, correctly built but permanently starved of
data. Fixed: both webhook handlers (`src/routes/webhooks.js`, Eversend and
Klasha) now write a plain-language notification when a transaction's
status resolves to success or failure (pending/processing states are
skipped — not worth notifying on). Best-effort only; a failed notification
insert never blocks webhook processing or the underlying transaction-status
update, which commits first.

## Audit conclusion

Full sweep complete: every screen's API calls cross-checked against real
backend routes (~45 distinct endpoints, zero mismatches), every "fake" or
"placeholder" string in the codebase traced to a comment describing
something already removed, dead-code scan across all 107 Dart files,
and manual review of auth, deposits, cards, corridors, gifts, contacts,
providers, and the fund-transfer/execute-transaction ledger flow.

**One real bug found and fixed**: Gifts screen was faking money movement
end-to-end — no backend call, fake success receipt, real balance
decremented for nothing. Now wired to the same real quote→payout pair
every other send flow uses.

**One real gap found and fixed**: Notifications tab (built this session)
had no writer anywhere — would have stayed permanently empty. Both
webhook handlers now write a notification on transaction success/failure.

**15 dead files identified**, none touching live money flows — safe to
delete, listed above with exact paths.

**One backend-ahead-of-frontend gap** (card fund/withdraw) documented,
not fixed — a feature-completeness item, not a correctness bug.

Everything else — the substantial majority of the codebase — checked out
clean: real API calls, real field-name matches, honest handling of
partial/unsupported coverage, no other fabricated success states.

## Follow-up fixes (after this audit was written)

### Card fund/withdraw now has a frontend
`POST /api/v1/cards/fund` and `POST /api/v1/cards/withdraw` were real,
working backend routes with no caller anywhere in the app. Fixed:
`wallet_screen.dart`'s card action row now has "Fund card" and "Withdraw"
actions alongside the existing Add/Details/Remove, opening a real
amount-entry sheet that calls these routes and refreshes the card list on
success.

### All 15 confirmed dead files deleted
All 15 files logged above as dead (13 orphaned screens/components + the
full Plaid integration + the unused icon-font utility) were re-verified
unreferenced one more time, then deleted. File count went from 107 to 92
Dart files. The `plaid_flutter` package dependency in pubspec.yaml (not
included in this upload) can now also be safely dropped — nothing in the
app imports it anymore.

### Crypto withdrawal corrected, not just flagged
The original crypto withdrawal implementation was built on an educated
guess at a direct `POST /crypto/withdraw` endpoint, clearly flagged as
unverified. Went back to Eversend's full API reference (their actual
sidebar navigation, not marketing copy) and confirmed definitively:
**Eversend's crypto API has no withdrawal/send endpoint at all** — it's
receive-only by design ("Fetch Assets Chains, Create Crypto Address, Fetch
Addresses, Fetch Transactions, Receive Crypto"). Their own docs describe
the intended flow explicitly: exchange the coin to fiat, then send via the
normal bank/mobile money rail.

Rewrote both sides to match this confirmed reality:
- `Backend/src/routes/crypto.js`'s `/withdraw` route now calls Eversend's
  confirmed `POST /exchanges/quotation` and `POST /exchanges` endpoints —
  a real, sourced coin-to-fiat conversion — instead of a guessed path.
- `withdraw_screen.dart`'s crypto flow no longer asks for a destination
  crypto wallet address (which the API could never act on). It now
  exchanges the coin to cash in the wallet, then hands off to the same
  `GlobalBankTransferScreen` every other withdrawal method uses to
  actually send the money out.



# Dutch Remit — Production Codebase

> Cross-border remittance platform. Send money to 32 countries across Africa, Europe and the US.

---

## Architecture

| Layer | Technology |
|---|---|
| Mobile app | Flutter (Dart) |
| Backend | Node.js / Express — hosted on Railway |
| Database / Auth | Supabase (Postgres + Row Level Security) |
| Payment rails | Eversend (primary — all live corridors) |
| Per-user ledger | `wallet_ledger` table in Supabase |

---

## Live Eversend Corridors (32 countries — confirmed 2026-09)

**Africa (MoMo + Bank):** CM · GH · KE · NG · UG  
**Africa (MoMo only):** RW · TZ · ZM · SN · CI  
**Europe (Bank/SEPA):** AT · BE · CY · DE · EE · FI · FR · GB · GR · HR · IE · IT · LT · LU · LV · MT · NL · PT · SI · SK  
**Americas:** US  
**Wallet-only:** ZA

---

## Backend

### Setup

```bash
cd Backend
npm install
cp .env.example .env   # fill in all secrets
npm start
```

### Required environment variables

```
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
EVERSEND_CLIENT_ID=
EVERSEND_CLIENT_SECRET=
EVERSEND_WEBHOOK_SECRET=     # from Eversend dashboard → Settings → Webhook
JWT_SECRET=
PORT=3000
```

### Routes

| Prefix | File | Purpose |
|---|---|---|
| `/api/v1/auth` | `routes/auth.js` | Login, OTP, register, session restore |
| `/api/v1/collections` | `routes/collections.js` | Deposit (MoMo). Min XAF 700. Immediate wallet credit on success. |
| `/api/v1/payouts` | `routes/payouts.js` | Send abroad — all Eversend corridors |
| `/api/v1/rates` | `routes/rates.js` | Quotation, corridor-methods, currency swap |
| `/api/v1/wallets` | `routes/wallets.js` | Per-user balance (`wallet_ledger`) |
| `/api/v1/cards` | `routes/cards.js` | Virtual cards — full lifecycle |
| `/api/v1/transactions` | `routes/transactions.js` | History (Supabase, normalized for Flutter) |
| `/api/v1/rewards` | `routes/rewards.js` | Social tasks + points (20pts = free card + $3) |
| `/api/v1/webhooks` | `routes/webhooks.js` | Eversend event processing (idempotent) |
| `/robots.txt`, `/sitemap.xml` | `routes/seo.js` | SEO + social handles |

### Supabase — run once

```sql
-- Core schema
supabase/schema.sql

-- Rewards tables (run after schema)
supabase_rewards_migration.sql
```

---

## Wallet balance architecture

```
User deposits XAF via MoMo
    → Eversend confirms (polling in /collections/momo)
    → wallet_ledger immediately credited (no webhook dependency)
    → Flutter calls syncBalanceFromEversend() → reads /wallets/my-balance
    → Flutter delayed re-sync after 4s (safety net)

User sends money
    → payouts/send debits wallet_ledger
    → Flutter syncs immediately + delayed 5s re-sync

User funds a card
    → cards/fund calls debitIfSufficient (debits wallet_ledger)
    → Flutter refreshes card list + syncs main balance immediately + 3s delayed re-sync

User withdraws from card
    → cards/withdraw credits wallet_ledger
    → Flutter refreshes card list + syncs main balance immediately + 3s delayed re-sync
```

**Never use** `GET /api/v1/wallets` for user balance display — this is the **business Eversend account**, shared across all users. Always use `GET /api/v1/wallets/my-balance`.

---

## Rewards / Social Tasks

20 points = free virtual card + $3 top-up

| Platform | Action | Points | Type |
|---|---|---|---|
| YouTube `@Dutch.Inc.Platforms` | Subscribe | 1 | One-time |
| Instagram `@dutchincplatforms` | Follow | 1 | One-time |
| TikTok `@dutch.inc.platforms` | Follow | 1 | One-time |
| YouTube / Instagram / TikTok | Like | 1 each | Daily |
| YouTube / Instagram / TikTok | Comment | 1 each | Daily |
| YouTube / Instagram / TikTok | Share | 1 each | Daily |

---

## Known open items (pre-launch)

1. **Top up Eversend business account** — currently at -$0.59 USD. All payouts will fail until funded.
2. **Set `EVERSEND_WEBHOOK_SECRET`** in Railway from Eversend dashboard → Settings → Webhook.
3. **Currency swap token** — Eversend returns `token: null` on exchange quotations for this account type. Swap falls back to direct-param execution. Confirm with Eversend account manager.
4. **Payout execution** — deferred pending Eversend account funding. Quotations confirmed live on all 32 corridors.

---

## Flutter app

```bash
flutter pub get
flutter run
```

### Key screens

| Screen | Purpose |
|---|---|
| `africa_corridor_screen` | Diaspora→Africa + Africa→Africa MoMo/bank |
| `global_bank_transfer_screen` | Europe + US bank transfer |
| `mobile_money_deposit_screen` | XAF/MoMo deposit (min 700 XAF) |
| `mobile_money_withdrawal_screen` | MoMo withdrawal |
| `currency_swap_screen` | Wallet currency swap |
| `wallet_screen` | Virtual card management |
| `create_virtual_card_screen` | New card + KYC |
| `rewards_hub_screen` | Social tasks + points redemption |
| `all_transaction_activities_screen` | Transaction history |

### Balance sync pattern (all money-moving screens)

```dart
// Immediate sync
await Provider.of<UserLoginStateProvider>(context, listen: false)
    .syncBalanceFromEversend(widget.userAuthKey);

// Delayed safety net (3–5 seconds depending on operation speed)
Future.delayed(const Duration(seconds: 5), () {
  if (!mounted) return;
  Provider.of<UserLoginStateProvider>(context, listen: false)
      .syncBalanceFromEversend(widget.userAuthKey);
});
```

---

## Social / SEO

- YouTube: https://www.youtube.com/@Dutch.Inc.Platforms
- Instagram: https://www.instagram.com/dutchincplatforms
- TikTok: https://www.tiktok.com/@dutch.inc.platforms
- Sitemap: `GET /sitemap.xml`
- Structured data: `GET /structured-data.json`

---

## PWA — Progressive Web App

Dutch Remit ships as a full offline-first PWA alongside the native mobile app.

### What's offline-capable

| Feature | Online | Offline |
|---|---|---|
| App shell, navigation, all UI | ✅ | ✅ |
| Balance display | Live | Last cached value + "You're offline" banner |
| Transaction history | Live | Last cached list |
| Card list | Live | Last cached list |
| Exchange rate quotes | Live | Blocked with clear message |
| Send money / Deposit / Swap | Live | Blocked — OfflineActionGuard |
| Corridor / country data | Live | Cached 24h |
| Bank lists | Live | Cached 12h |

### First-launch experience

1. User opens the PWA for the first time
2. `OfflineSetupScreen` appears: *"Downloading files to enable offline use"*
3. Service worker caches all Flutter assets (~15–25 MB) with a real progress bar
4. Heavy assets (WASM, CanvasKit) download silently after 100% is shown
5. `shared_preferences` flag `offline_setup_complete = true` is saved
6. User goes directly to login — never sees setup screen again

### PWA vs Browser vs Native

| Context | Behaviour |
|---|---|
| Native iOS/Android | Unchanged — existing onboarding flow |
| PWA (installed, standalone) | Skips onboarding → Login directly. No URL bar. Offline setup on first launch. |
| Browser (not installed) | App shown with "Install Dutch Remit" banner at bottom. No intro pages. |

Detection is via `window.matchMedia('(display-mode: standalone)')` + `navigator.standalone` (iOS).

### Build

```bash
# From project root
chmod +x build_web.sh
./build_web.sh

# This runs:
# 1. flutter pub get
# 2. flutter build web --release --web-renderer canvaskit
# 3. Copies build/web → Backend/public/
# 4. Copies custom sw.js (overrides Flutter's generated one)
```

### Caching strategy

| Resource | Strategy | Cache duration |
|---|---|---|
| `index.html`, `sw.js`, `manifest.json` | No-cache | Always fresh |
| `main.dart.js`, `*.wasm`, fonts, assets | Cache-First | Permanent (content-hashed) |
| Balance, transactions, cards (API reads) | Network-First → stale | 10 min stale TTL |
| Send, deposit, swap (financial writes) | Network-Only | Never cached |

### Deployment targets

**Railway** (current backend):
- Uses `railway.json` — builds Flutter web then starts Express
- Flutter web output served from `Backend/public/`
- `FLUTTER_WEB_PATH` env var overrides the public path

**Netlify** (frontend only):
- `web/_headers` sets correct cache headers
- `web/_redirects` handles SPA routing

**Vercel** (frontend only):
- `vercel.json` in project root

### Offline guard pattern

Every financial action is wrapped:
```dart
Future<void> _confirmSend() async {
  if (!await OfflineActionGuard.check(context, action: 'Send Money')) return;
  // ... proceed
}
```

Shows a bottom sheet: *"You're offline — Send Money requires an internet connection"* with a "Wait for connection" option that auto-proceeds when reconnected.

### File structure

```
web/
├── index.html          # PWA entry, SW registration, A2HS prompt
├── manifest.json       # PWA manifest (standalone, theme, icons)
├── sw.js               # Custom service worker (cache-first + progress)
├── offline.html        # Fallback page when truly offline first launch
├── _headers            # Netlify cache headers
├── _redirects          # Netlify SPA fallback
└── icons/
    ├── Icon-48.png
    ├── Icon-96.png
    ├── Icon-192.png
    └── Icon-512.png

lib/
├── screens/
│   ├── offline_setup_screen.dart   # One-time first-launch download screen
│   └── pwa_bootstrap.dart          # PWA/browser/native routing
├── services/
│   ├── connectivity_service.dart   # Network monitoring (connectivity_plus)
│   ├── offline_action_guard.dart   # Blocks financial actions when offline
│   ├── offline_cache.dart          # Hive-backed API response cache
│   ├── offline_setup_bridge.dart   # SW progress → Flutter stream
│   └── offline_storage.dart        # Offline-aware data fetcher facade
├── methods/
│   └── download_helper.dart        # Progress % / bytes / ETA helpers
└── utilities/
    ├── pwa_detection.dart          # Conditional import facade
    └── platform/
        ├── pwa_detection_stub.dart # Mobile/desktop stub
        └── pwa_detection_web.dart  # Real web implementation (dart:html)
```

---

## Support

Email: support@dutchremit.com

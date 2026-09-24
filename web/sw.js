/**
 * Dutch Remit — Production Service Worker v1
 * ───────────────────────────────────────────
 * Strategies:
 *   App shell (JS, WASM, fonts, icons, HTML)   → Cache-First
 *   Safe API reads (balance, history, cards)    → Network-First → stale fallback
 *   Financial writes (send, deposit, swap)      → Network-Only  (never cached)
 *
 * First-launch progress messages to Flutter:
 *   { type: 'INSTALL_PROGRESS', cached: N, total: T }  — after each file
 *   { type: 'INSTALL_COMPLETE' }                        — when all required files are cached
 *   { type: 'INSTALL_ERROR',   error: '...' }           — on failure
 */

const CACHE_VERSION = 'v2';
const SHELL_CACHE   = `dr-shell-${CACHE_VERSION}`;

// ── API paths safe to serve stale (read-only, no money movement) ───────────
const STALE_OK = [
  '/api/v1/rates/corridor-methods',
  '/api/v1/payouts/countries',
  '/api/v1/payouts/banks',
];

// ── API paths that MUST reach the network (financial writes) ───────────────
const NETWORK_ONLY = [
  '/api/v1/payouts/send',
  '/api/v1/collections/otp',
  '/api/v1/collections/momo',
  '/api/v1/rates/exchange',
  '/api/v1/rates/quotation',
  '/api/v1/rates/exchange-quotation',
  '/api/v1/cards/fund',
  '/api/v1/cards/withdraw',
  '/api/v1/cards/freeze',
  '/api/v1/cards/unfreeze',
  '/api/v1/cards/terminate',
  '/api/v1/rewards/redeem',
  '/api/v1/rewards/complete',
  '/Dutch%20Remit/v2/execute-transaction',
  '/Dutch%20Remit/v3/user/',
  '/api/v1/auth/',
];

// ── Guaranteed shell (fetched before manifest is available) ────────────────
const BOOT_SHELL = [
  '/',
  '/index.html',
  '/manifest.json',
  '/offline.html',
  '/favicon.png',
];

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

const broadcast = (msg) =>
  self.clients.matchAll({ includeUncontrolled: true }).then(clients =>
    clients.forEach(c => c.postMessage(msg))
  );

const pathMatches = (url, list) => {
  try {
    const p = new URL(url).pathname;
    return list.some(prefix => p.startsWith(prefix));
  } catch { return false; }
};

const fetchWithRetry = async (url, retries = 3, delayMs = 600) => {
  for (let i = 0; i < retries; i++) {
    try {
      const r = await fetch(url, { cache: 'no-store' });
      if (r.ok || r.status === 0) return r;
    } catch (_) {}
    if (i < retries - 1) await new Promise(r => setTimeout(r, delayMs * (i + 1)));
  }
  return null;
};

// ─────────────────────────────────────────────────────────────────────────────
// INSTALL — two-phase pre-cache with progress reporting
// ─────────────────────────────────────────────────────────────────────────────

self.addEventListener('install', event => {
  self.skipWaiting();

  event.waitUntil((async () => {
    const cache = await caches.open(SHELL_CACHE);

    // ── Phase 1: Build the full asset list ───────────────────────────────
    let primaryUrls  = [...BOOT_SHELL];
    let secondaryUrls = [];  // cached silently AFTER the user sees 100%

    try {
      const [assetManifest, fontManifest] = await Promise.all([
        fetch('/AssetManifest.json').then(r => r.ok ? r.json() : {}).catch(() => ({})),
        fetch('/FontManifest.json').then(r => r.ok ? r.json() : []).catch(() => []),
      ]);

      // All Flutter assets declared in pubspec
      const flutterAssets = Object.keys(assetManifest).map(k =>
        k.startsWith('/') ? k : `/${k}`
      );

      // Font files (often large — keep in primary set)
      const fontFiles = fontManifest.flatMap(f =>
        (f.fonts || []).map(ff => ff.asset ? (ff.asset.startsWith('/') ? ff.asset : `/${ff.asset}`) : null)
      ).filter(Boolean);

      // Core Flutter web runtime
      const coreRuntime = [
        '/flutter.js',
        '/main.dart.js',
        '/flutter_service_worker.js',
        '/version.json',
        '/AssetManifest.json',
        '/FontManifest.json',
      ];

      const seen = new Set();
      const dedup = urls => urls.filter(u => {
        if (!u || seen.has(u)) return false;
        seen.add(u); return true;
      });

      // Primary = runtime + fonts + small assets (everything needed for first paint)
      const allAssets = dedup([...BOOT_SHELL, ...coreRuntime, ...fontFiles, ...flutterAssets]);

      // Assets > 2 MB (WASM, CanvasKit) → secondary (silent, after progress bar)
      // We can't easily know file sizes before fetching, so we split by path pattern
      const isHeavy = url =>
        url.endsWith('.wasm') ||
        url.includes('canvaskit') ||
        url.includes('.br') ||   // brotli compressed bundles
        url.includes('.gz');

      primaryUrls   = allAssets.filter(u => !isHeavy(u));
      secondaryUrls = allAssets.filter(isHeavy);

    } catch (err) {
      console.warn('[DR SW] Asset manifest failed — using boot shell', err);
    }

    // ── Phase 2: Cache primary assets WITH progress messages ─────────────
    const total = primaryUrls.length;
    let cached  = 0;
    let failed  = [];

    for (const url of primaryUrls) {
      try {
        const res = await fetchWithRetry(url);
        if (res) {
          await cache.put(url, res);
        } else {
          failed.push(url);
        }
      } catch (err) {
        failed.push(url);
        console.warn(`[DR SW] Primary cache skip: ${url}`, err.message);
      }
      cached++;
      broadcast({ type: 'INSTALL_PROGRESS', cached, total });
    }

    // ── Phase 3: Heavy assets — download silently before completion ──────
    // These files are not counted in the visible primary progress, but the
    // setup is not complete until they are cached or an error is reported.
    for (const url of secondaryUrls) {
      try {
        const res = await fetchWithRetry(url, 2, 1000);
        if (res) {
          await cache.put(url, res);
        } else {
          failed.push(url);
        }
      } catch (err) {
        failed.push(url);
        console.warn(`[DR SW] Secondary cache skip: ${url}`, err.message);
      }
    }

    if (failed.length > 0) {
      await broadcast({
        type: 'INSTALL_ERROR',
        error: `Unable to cache ${failed.length} required file(s).`,
        failed,
      });
      return;
    }

    await broadcast({ type: 'INSTALL_COMPLETE', cached, total });
    console.log(`[DR SW] Offline cache complete: ${cached} primary + ${secondaryUrls.length} secondary files`);

  })());
});

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVATE — clean old caches, claim all tabs
// ─────────────────────────────────────────────────────────────────────────────

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    await self.clients.claim();
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter(k => k !== SHELL_CACHE)
        .map(k => { console.log('[DR SW] Purging old cache:', k); return caches.delete(k); })
    );
  })());
});

// ─────────────────────────────────────────────────────────────────────────────
// FETCH — per-request routing strategy
// ─────────────────────────────────────────────────────────────────────────────

self.addEventListener('fetch', event => {
  const { request } = event;
  const url = request.url;

  // Skip non-GET and non-http(s)
  if (request.method !== 'GET') return;
  if (!url.startsWith('http')) return;

  // Skip browser-extension requests
  if (url.startsWith('chrome-extension://') || url.startsWith('moz-extension://')) return;

  const isApi = url.includes('/api/v1/') || url.includes('/Dutch%20Remit/');

  // ── NETWORK-ONLY: financial writes — never touch the cache ────────────
  if (isApi && pathMatches(url, NETWORK_ONLY)) return;   // pass through

  // ── NETWORK-FIRST: public API reads only ───────────────────────────────
  if (isApi && pathMatches(url, STALE_OK)) {
    event.respondWith(networkFirstStale(request, 4000));
    return;
  }

  // Never put unknown or authenticated API responses in the shared shell
  // cache. App-level storage can add user-scoped caching deliberately.
  if (isApi) return;

  // ── CACHE-FIRST: app shell + all Flutter assets ────────────────────────
  event.respondWith(cacheFirst(request));
});

// ─── Cache-First (app shell) ──────────────────────────────────────────────
async function cacheFirst(request) {
  const cached = await caches.match(request);
  if (cached) return cached;

  try {
    const net = await fetch(request.clone());
    if (net.ok || net.status === 0) {
      const c = await caches.open(SHELL_CACHE);
      c.put(request, net.clone());
    }
    return net;
  } catch (_) {
    if (request.mode === 'navigate') {
      return caches.match('/offline.html') || caches.match('/index.html');
    }
    return new Response('', { status: 408, statusText: 'Offline' });
  }
}

// ─── Network-First with stale fallback ────────────────────────────────────
async function networkFirstStale(request, timeoutMs) {
  try {
    const net = await Promise.race([
      fetch(request.clone()),
      new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), timeoutMs)),
    ]);

    return net;
  } catch (_) {
    if (request.mode === 'navigate') {
      return caches.match('/offline.html');
    }
    return new Response(
      JSON.stringify({ error: 'offline', cached: false,
        message: 'No internet connection. Please reconnect to see live data.' }),
      { status: 503, headers: { 'Content-Type': 'application/json',
        'X-Dutch-Remit-Offline': 'true' } }
    );
  }
}

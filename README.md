# Deploying Dutch Remit to dutchremit.dubiabank.com on Netlify

## Why drag-and-drop deploy can't make Plaid work

If you've been deploying by dragging the `build/web` folder into the
Netlify dashboard: that method only ever uploads static files. It has no
build step, so it can't read `netlify.toml`, can't see the
`netlify/functions/` folder, and can't run `npm install` for the
functions' dependencies. There's no configuration that changes this —
it's a hard limit of how that deploy method works, not a setup mistake.

**The fix is one terminal command, not a rebuild of anything.** All the
files are already correct and in place:

```bash
npm install -g netlify-cli   # one-time, if you don't have it yet
cd /path/to/this/project
npm install                  # installs the functions' dependencies
netlify login                # one-time, opens a browser to authenticate
netlify link                 # connects this folder to your existing dutchremit.dubiabank.com site
flutter build web             # builds the Flutter app as usual
netlify deploy --prod        # uploads BOTH the site and the functions together
```

After `netlify deploy --prod` finishes, `/api/plaid/health` will return
real JSON instead of a 404, and every Plaid feature will work — nothing
in the code needs to change for this. You only need to run this sequence
once to switch over; after that, every future `netlify deploy --prod` (or
connecting a Git repo so it deploys automatically — see below) carries
the functions along automatically.

---

This project has two parts that deploy together as one Netlify site:

1. **The Flutter web app** — static files, built with `flutter build web`.
2. **The Plaid backend** — `netlify/functions/*.js`, deployed as Netlify
   Functions. This is the only place your Plaid `client_id`/`secret` ever
   exist; the Flutter app never sees them.

Both ship from the same repo, same deploy, same domain. No separate server
to host or pay for.

---

## 1. One-time setup: Upstash Redis (free)

The functions need somewhere to remember which bank account is linked to
which user between requests (Netlify Functions don't keep anything in
memory between calls, so this can't just live in a variable).

1. Go to console.upstash.com, sign up free.
2. Create a Redis database (any region close to where most users will be —
   us-east-1 is a safe default).
3. On the database's page, open the REST API tab and copy:
   - UPSTASH_REDIS_REST_URL
   - UPSTASH_REDIS_REST_TOKEN

Free tier covers this comfortably: 500,000 commands/month, 256 MB storage.

## 2. One-time setup: Netlify environment variables

In your Netlify site -> Site configuration -> Environment variables, add:

| Key | Value |
|---|---|
| PLAID_CLIENT_ID | your Plaid client ID |
| PLAID_SECRET | your Sandbox secret (swap for production secret later) |
| PLAID_ENV | sandbox |
| UPSTASH_REDIS_REST_URL | from step 1 |
| UPSTASH_REDIS_REST_TOKEN | from step 1 |
| ALLOWED_ORIGIN | https://dutchremit.dubiabank.com |

See .env.example for the same list with comments.

## 3. Connect your domain

In Netlify -> Domain management, add dutchremit.dubiabank.com as a
custom domain. Since this is a subdomain, you'll add a CNAME record at
whoever manages DNS for dubiabank.com, pointing
dutchremit.dubiabank.com -> the *.netlify.app address Netlify gives you.
Netlify provisions HTTPS for it automatically once DNS resolves.

## 4. Build the Flutter web app

Locally (or in CI before pushing):

```
flutter pub get
flutter build web
```

This produces build/web/ — exactly what netlify.toml's
publish = "build/web" expects. Commit the source, not the build
output — Netlify rebuilds it fresh each deploy.

If you want Netlify itself to run flutter build web (so you never
build locally), you'd need a build image with the Flutter SDK available,
which Netlify's default Node image doesn't have. The simplest reliable
setup is: build Flutter locally or in a separate CI step (e.g. a GitHub
Action using subosito/flutter-action), then let Netlify just publish
the resulting build/web folder and deploy the functions. This is what
the current netlify.toml assumes.

## 5. Install function dependencies and deploy

```
npm install
git push
```

(if connected to Netlify via Git, this triggers the deploy)

Or with the Netlify CLI directly:

```
npm install -g netlify-cli
netlify deploy --prod
```

## 6. Verify it's wired up correctly

Once deployed:

```
curl https://dutchremit.dubiabank.com/api/plaid/health
# {"ok":true,"environment":"sandbox"}
```

If that works, the redirects, functions, and environment variables are all
correctly connected. Then open the app itself and try Card -> Connect a
bank — it should open the real Plaid Link popup.

---

## Developing locally before deploying

Use the Netlify CLI's `netlify dev` — it runs your functions locally
and proxies redirects exactly like production, so you're testing the
real /api/plaid/* paths, not a different local setup:

```
npm install -g netlify-cli
netlify dev
```

This serves everything at http://localhost:8888. While doing this,
temporarily point PlaidApiConstants.baseUrl (in
lib/resources/plaid_api_constants.dart) at http://localhost:8888,
then switch it back to the production domain before deploying.

You'll also need a local .env file (gitignored) with the same variables
as the Netlify dashboard for netlify dev to pick up — see .env.example.

---

## Going live later (Sandbox -> Production)

Two environment variable changes, in the Netlify dashboard:

```
PLAID_ENV: sandbox -> production
PLAID_SECRET: <sandbox secret> -> <production secret>
```

Redeploy after saving the env vars. Nothing in netlify/functions/*.js
or anywhere in the Flutter app needs to change.

Before flipping that switch for real users:
1. Apply for Plaid Production access (takes a few days for review).
2. Apply for the Transfer product specifically if you want real
   bank-to-bank transfers, not just linking/balances — separate approval
   from basic Production access.
3. The Upstash Redis store is genuinely production-capable as-is (it's a
   real managed database, not a demo shortcut) — but DEMO_RECIPIENTS in
   netlify/functions/_shared/db.js is a hardcoded fake user list and
   should be swapped for a real lookup against your actual users.

## What's simulated vs. what's real

Real, actually talking to Plaid:
- The bank picker popup (Plaid Link) — real institution list, real
  Sandbox login flow.
- Account linking, balances, transaction history — genuine Plaid Sandbox
  data.
- Transfer authorization/creation — real Plaid Transfer API calls, if
  Transfer is enabled on your account.

Simulated, because this is how Plaid's own Sandbox behaves:
- A created transfer sits at "pending" until you call the simulate
  endpoint — that's Plaid Sandbox's documented behavior, not a shortcut.
- The "inject a live transaction" feature uses Plaid's own
  /sandbox/transactions/create test endpoint.

## If a function returns a CORS error

Check that ALLOWED_ORIGIN in your environment variables exactly matches
the origin the app is served from (https://dutchremit.dubiabank.com, no
trailing slash). A mismatch here is the most common reason a browser
blocks the request while curl (which ignores CORS) works fine.

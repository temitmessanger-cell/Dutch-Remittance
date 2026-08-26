# Dutch Remit Chat Work Summary

Date: 2026-08-25

## Problem Investigated

The deployed Netlify frontend could not log users in because the browser tried to call:

`http://localhost:4000/api/v1/auth/otp/request`

The browser also reported a Hive web storage error for the local box:

`dutch_remit_user_data`

## Work Completed

### Transfer and payout features

Added and updated the backend and Flutter transfer flows for global
transfers, payout corridors, mobile-money deposits and withdrawals,
bank transfers, cards, quotations, and country data.

### Frontend API configuration

Updated `lib/resources/api_constants.dart` so the application defaults to the live Railway backend:

`https://dutch-remittance-production.up.railway.app`

This removes the production dependency on `localhost:4000`. The existing `API_BASE_URL` build-time override remains available for other environments.

### Hive web storage recovery

Updated `lib/main.dart` to recover from a stale or broken browser Hive object store for `dutch_remit_user_data`:

1. Try to open the user-data box.
2. If opening fails, delete the broken local box from the browser database.
3. Reopen the box so application startup can continue.

Only the local cached user-data box is removed during recovery. The Supabase database is not changed.

### Login and protected-flow fixes

- Removed the `Continue as Guest` option from the login screen.
- Updated onboarding session detection so cached profile data cannot
  bypass login without a valid persistent authentication token.
- Added a deposit guard so mobile-money OTP requests are not sent when
  the user has no valid authentication token.
- The backend correctly returns `401 Unauthorized` for protected routes
  when no valid token is supplied.

### Missing image handling

Updated dashboard image rendering so null or empty avatar values fall
back to initials instead of generating URLs ending in `/null`.

### Eversend proxy routing

Updated `Backend/src/eversendClient.js` to use the Webshare proxy when
`OUTBOUND_PROXY_URL` is configured. Eversend token and API requests now
use `HttpsProxyAgent`, `httpsAgent`, and `proxy: false`.

Added support for an independent `EVERSEND_ORIGIN` variable so the
origin registered with Eversend can differ from the frontend CORS
origin.

## Verification

- Railway health endpoint responded successfully with HTTP `200`:
  `https://dutch-remittance-production.up.railway.app/health`
- The Railway endpoint returned CORS headers for:
  `https://dutchremit.dubiabank.com`
- The compiled web bundle contained the Railway hostname.
- The compiled web bundle did not contain `localhost:4000`.
- `flutter build web --release` completed successfully.
- Flutter analysis found only existing style/info messages in `main.dart`; no compilation error was introduced.
- A direct local test through Webshare reached Eversend successfully:
  token request `200` and payout-countries request `200`.
- The Webshare exit IP tested as `66.78.34.173`.
- Railway was tested repeatedly: health and CORS succeed, but the
  live Eversend-backed payout-countries route returned `401` while the
  Railway runtime was still using an older deployment/configuration.
- The deployed Railway file was confirmed at one point to be the old
  commit `3f2027e16ce97aa50410c29fc77af293bf452f82`, without proxy support.

## Git Commits

The following relevant commits were created on `main`:

- `05e901e` - Add global transfer and payout corridors
- `18e6698` - Point web client at Railway backend
- `12b112f` - Require login before protected actions
- `301ba1e` - Guard deposit requests with login session
- `bf49c6a` - Harden authenticated provider flows

The latest commit was successfully pushed to GitHub. Local and remote
`main` point to `bf49c6a`.

## Remaining Deployment Steps

The commits were pushed successfully to:

`https://github.com/temitmessanger-cell/Dutch-Remittance`

The latest successful push reported:

`b9caed0..bf49c6a main -> main`

Railway must be connected to this repository and the `main` branch to
automatically deploy the backend changes.

```powershell
git push origin main
```

Then rebuild and deploy the frontend to Netlify. The generated `build/web` directory contains the production frontend:

```powershell
flutter build web --release
netlify deploy --prod --dir=build/web
```

After deployment, clear the website's browser storage once and reload
it so the Hive recovery code runs against the updated bundle.

## Current Eversend Status

The Eversend credentials and Webshare proxy work from the local
workspace. Railway health and CORS also work. If Railway's
`/api/v1/payouts/countries` endpoint still returns `401 Invalid request
origin`, the active Railway service is not using the same proxy/origin
configuration or has not deployed the latest backend commit.

Required Railway variables:

```text
OUTBOUND_PROXY_URL=<current Webshare proxy URL>
EVERSEND_ORIGIN=https://dutchremit.dubiabank.com
EVERSEND_CLIENT_ID=<current Eversend client ID>
EVERSEND_CLIENT_SECRET=<current Eversend client secret>
EVERSEND_WEBHOOK_SECRET=<Eversend webhook signing secret>
ALLOWED_ORIGIN=https://dutchremit.dubiabank.com
NODE_ENV=production
```

The Webshare proxy exit IP must be whitelisted in Eversend. No payout,
deposit, or other money-moving operation was executed during testing.

## Security Action Required

A GitHub personal access token, Eversend credentials, and a Webshare
proxy URL containing credentials were exposed in chat. They must be
revoked or rotated immediately. Secret values are intentionally not
recorded in this file.

## Deployment Architecture

- Frontend: Netlify
- Backend: Railway
- Database and authentication: Supabase

The frontend communicates with the backend over HTTPS. The backend communicates with Supabase using Railway environment variables; no database credentials should be placed in the Flutter frontend or committed to Git.

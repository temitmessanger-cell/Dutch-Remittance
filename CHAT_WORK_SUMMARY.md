# Dutch Remit Chat Work Summary

Date: 2026-08-25

## Problem Investigated

The deployed Netlify frontend could not log users in because the browser tried to call:

`http://localhost:4000/api/v1/auth/otp/request`

The browser also reported a Hive web storage error for the local box:

`dutch_remit_user_data`

## Work Completed

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

## Verification

- Railway health endpoint responded successfully with HTTP `200`:
  `https://dutch-remittance-production.up.railway.app/health`
- The Railway endpoint returned CORS headers for:
  `https://dutchremit.dubiabank.com`
- The compiled web bundle contained the Railway hostname.
- The compiled web bundle did not contain `localhost:4000`.
- `flutter build web --release` completed successfully.
- Flutter analysis found only existing style/info messages in `main.dart`; no compilation error was introduced.

## Git Commits

The following commits were created locally on `main`:

- `05e901e` - Add global transfer and payout corridors
- `18e6698` - Point web client at Railway backend

The local branch was 8 commits ahead of `origin/main` after these changes.

## Remaining Deployment Steps

The GitHub push was rejected with HTTP `403` because the configured GitHub account did not have write permission for the repository.

After authenticating with an account that has write access, push the commits:

```powershell
git push origin main
```

Then rebuild and deploy the frontend to Netlify. The generated `build/web` directory contains the production frontend:

```powershell
flutter build web --release
netlify deploy --prod --dir=build/web
```

After deployment, clear the website's browser storage once and reload it so the Hive recovery code runs against the updated bundle.

## Security Action Required

A GitHub personal access token was pasted into chat. It must be revoked immediately in GitHub and replaced with a new credential if needed. The token value is intentionally not recorded in this file.

## Deployment Architecture

- Frontend: Netlify
- Backend: Railway
- Database and authentication: Supabase

The frontend communicates with the backend over HTTPS. The backend communicates with Supabase using Railway environment variables; no database credentials should be placed in the Flutter frontend or committed to Git.

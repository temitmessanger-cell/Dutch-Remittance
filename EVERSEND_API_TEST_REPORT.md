# Eversend API Test Report

Date: 2026-08-25

## Scope

This report records safe, read-only connectivity tests for the Dutch Remit backend and Eversend API. No OTP was sent, and no deposit, payout, card transaction, or other money-moving operation was performed.

## Test Results

### Direct Eversend test through Webshare

The backend's local Eversend client was run with the configured Webshare proxy.

- Eversend token endpoint: `200`
- Token returned: yes
- Eversend payout-countries endpoint: `200`
- Webshare exit IP previously verified as: `66.78.34.173`
- Result: direct Eversend access works through the proxy.

### Railway health and CORS

- Railway health endpoint: `200 OK`
- Frontend origin: `https://dutchremit.dubiabank.com`
- CORS preflight for the auth endpoint: `204`
- `access-control-allow-origin`: `https://dutchremit.dubiabank.com`
- Result: Railway is online and browser cross-origin access is working.

### Railway Eversend proxy route

Endpoint tested:

`https://dutch-remittance-production.up.railway.app/api/v1/payouts/countries`

- Response: `401 Unauthorized`
- Result: the deployed Railway service is still not successfully authenticating its Eversend request.

## Diagnosis

The difference between the two tests isolates the problem to the Railway runtime deployment or its environment variables:

- Eversend credentials work.
- Webshare proxy credentials and routing work locally.
- Eversend accepts the request when it exits through the Webshare IP.
- Railway itself is healthy.
- CORS is not the cause of the Eversend failure.
- The Railway service is either missing the active proxy/origin variables, using stale values, running stale code, or is connected to a different Railway service than expected.

## Required Railway Runtime Variables

Set these on the exact Railway service serving `dutch-remittance-production.up.railway.app`:

```text
OUTBOUND_PROXY_URL=<current Webshare proxy URL>
EVERSEND_ORIGIN=https://dutchremit.dubiabank.com
EVERSEND_CLIENT_ID=<current Eversend client ID>
EVERSEND_CLIENT_SECRET=<current Eversend client secret>
EVERSEND_WEBHOOK_SECRET=<current Eversend webhook signing secret>
ALLOWED_ORIGIN=https://dutchremit.dubiabank.com
NODE_ENV=production
```

The Webshare exit IP must be present in Eversend's production IP whitelist.

## Source and Deployment State

GitHub repository:

`https://github.com/temitmessanger-cell/Dutch-Remittance`

The latest verified GitHub `main` commit is:

`fd43bd5 Fix top-up web build import`

The backend proxy fix is included in the repository history at commit `bf49c6a` (`Harden authenticated provider flows`).

The currently tested Railway deployment must be checked in Railway's deployment view. Its deployed source must include `Backend/src/eversendClient.js` with:

- `HttpsProxyAgent`
- `OUTBOUND_PROXY_URL`
- `httpsAgent: proxyAgent` in token requests
- `httpsAgent: proxyAgent` in authenticated requests
- `proxy: false`
- `EVERSEND_ORIGIN` handling

## Frontend Status

The Flutter web build was generated with:

```powershell
flutter build web --release --dart-define=API_BASE_URL=https://dutch-remittance-production.up.railway.app
```

The generated `build/web/main.dart.js` contains the Railway URL and does not contain `http://localhost:4000`.

## Final Conclusion

The Eversend API and Webshare proxy are functional. The unresolved failure is only on the live Railway service path. After the exact variables are added to the active Railway service and that service is redeployed, retest the Railway payout-countries endpoint. The expected result is HTTP `200`.

## Security

Credentials and proxy URLs were exposed during troubleshooting. Rotate the GitHub token, Eversend credentials, and Webshare proxy credentials before production use. Secret values are intentionally excluded from this report.

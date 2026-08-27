const axios = require('axios');
const { HttpsProxyAgent } = require('https-proxy-agent');

/**
 * Eversend's dashboard IP Whitelist only accepts requests from a
 * registered production IP. Railway has no static outbound IP, so
 * OUTBOUND_PROXY_URL (the same static-IP proxy used for Klasha calls
 * — see klashaClient.js) routes Eversend calls through that
 * whitelisted address too. Left unset, requests go out directly.
 */
const proxyUrl = process.env.OUTBOUND_PROXY_URL;

// See klashaClient.js for the full rationale: a single module-level
// proxy agent reused for the whole process lifetime develops a stale
// socket after the container has been up a while, causing intermittent
// 502s on requests that are otherwise perfectly valid. Building a fresh
// agent per request avoids this. Eversend hasn't hit it yet, but shares
// the same pattern, so we harden it here too.
function makeProxyAgent() {
  return proxyUrl ? new HttpsProxyAgent(proxyUrl) : undefined;
}

/**
 * Eversend's /auth/token endpoint separately requires an `Origin`
 * header matching the app's registered domain (confirmed live:
 * omitting it returns 401 "Invalid request origin" even from a whitelisted IP). 
 * EVERSEND_ORIGIN can override the frontend CORS origin when Eversend has a 
 * separate registered origin.
 */
const eversendOrigin =
  process.env.EVERSEND_ORIGIN?.trim() ||
  (process.env.ALLOWED_ORIGIN || '').split(',')[0].trim() ||
  undefined;

/**
 * Thin wrapper around the Eversend REST API.
 *
 * Docs: https://eversend.readme.io/reference/api-overview
 * Base URL: https://api.eversend.co/v1
 *
 * Auth: GET /auth/token with `clientId` and `clientSecret` headers
 * returns { status, token }. That token is then sent as a Bearer
 * token on every subsequent request. We cache it in memory and
 * refresh a little before it would realistically expire, so most
 * requests don't pay the extra round trip.
 */
class EversendClient {
  constructor({ baseUrl, clientId, clientSecret }) {
    this.baseUrl = baseUrl || 'https://api.eversend.co/v1';
    this.clientId = clientId;
    this.clientSecret = clientSecret;
    this._token = null;
    this._tokenExpiresAt = 0;
    // Eversend doesn't document a token TTL; refreshing every 20
    // minutes is a safe, conservative default that avoids ever
    // handing out a token the API has already rejected.
    this._tokenTtlMs = 20 * 60 * 1000;
  }

  async _getToken() {
    const now = Date.now();
    if (this._token && now < this._tokenExpiresAt) {
      return this._token;
    }
    if (!this.clientId || !this.clientSecret) {
      throw new Error(
        'EVERSEND_CLIENT_ID / EVERSEND_CLIENT_SECRET are not set. Add them to .env.'
      );
    }

    const response = await axios.get(`${this.baseUrl}/auth/token`, {
      headers: {
        clientId: this.clientId,
        clientSecret: this.clientSecret,
        ...(eversendOrigin ? { Origin: eversendOrigin } : {}),
      },
      httpsAgent: makeProxyAgent(),
      proxy: false,
    });

    const token = response.data?.token;
    if (!token) {
      throw new Error('Eversend did not return a token. Check your credentials.');
    }
    this._token = token;
    this._tokenExpiresAt = now + this._tokenTtlMs;
    return token;
  }

  /**
   * Makes an authenticated request against the Eversend API.
   * Automatically retries once on a 401 (in case the cached token
   * genuinely expired early) by forcing a fresh token.
   */
  async request({ method = 'GET', path, params, data, _retried = false }) {
    const token = await this._getToken();
    try {
      const response = await axios({
        method,
        url: `${this.baseUrl}${path}`,
        params,
        data,
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
          ...(eversendOrigin ? { Origin: eversendOrigin } : {}),
        },
        timeout: 20000,
        httpsAgent: makeProxyAgent(),
        proxy: false,
      });
      return response.data;
    } catch (err) {
      const status = err.response?.status;
      if (status === 401 && !_retried) {
        this._token = null;
        return this.request({ method, path, params, data, _retried: true });
      }
      // Normalize the error so route handlers can pass a clean shape
      // back to the Flutter app instead of leaking axios internals.
      // The final fallback ('Something went wrong...') is deliberately
      // generic rather than the raw axios message (e.g. "Request
      // failed with status code 403") — a user seeing an HTTP status
      // code in a plain-language app is confusing, not helpful, and
      // this fallback should rarely even trigger since Eversend's own
      // error responses almost always populate data.message/data.error.
      const message =
        err.response?.data?.message ||
        err.response?.data?.error ||
        (err.response ? 'Something went wrong on our end. Please try again.' : 'Could not reach Eversend right now. Please try again shortly.');
      const normalized = new Error(message);
      normalized.status = status || 502;
      normalized.details = err.response?.data;
      throw normalized;
    }
  }

  get(path, params) {
    return this.request({ method: 'GET', path, params });
  }

  post(path, data) {
    return this.request({ method: 'POST', path, data });
  }

  patch(path, data) {
    return this.request({ method: 'PATCH', path, data });
  }

  delete(path) {
    return this.request({ method: 'DELETE', path });
  }
}

const eversend = new EversendClient({
  baseUrl: process.env.EVERSEND_BASE_URL,
  clientId: process.env.EVERSEND_CLIENT_ID,
  clientSecret: process.env.EVERSEND_CLIENT_SECRET,
});

module.exports = { EversendClient, eversend };

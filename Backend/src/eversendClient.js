const axios = require('axios');

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
      },
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
        },
        timeout: 20000,
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
      const message =
        err.response?.data?.message ||
        err.response?.data?.error ||
        err.message ||
        'Eversend request failed';
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

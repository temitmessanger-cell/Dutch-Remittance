const axios = require('axios');
const crypto = require('crypto');
const { HttpsProxyAgent } = require('https-proxy-agent');

/**
 * When Klasha requires IP-whitelisted access and Railway's own plan
 * has no static outbound IP, OUTBOUND_PROXY_URL points at a
 * static-IP proxy (e.g. QuotaGuard Static IP) so calls to Klasha
 * always leave from the same, whitelistable address. Left unset,
 * requests go out directly as before — nothing else changes.
 */
const proxyUrl = process.env.OUTBOUND_PROXY_URL;
const proxyAgent = proxyUrl ? new HttpsProxyAgent(proxyUrl) : undefined;

/**
 * Klasha is the fallback for the currencies Eversend's 10 confirmed
 * corridors don't cover. Docs: https://developers.klasha.com
 *
 * Confirmed payout coverage (as of this pass, from
 * developers.klasha.com/transfers/payout directly): NGN, ZAR, GHS
 * (beta), KES (beta). That's the real list — see the note above
 * KLASHA_PAYOUT_ENDPOINTS in corridors.js for why an earlier, wider
 * list here was wrong and has been corrected.
 *
 * Auth: POST {{base_url}}/auth/account/v2/login with your merchant
 * credentials returns a bearer token, sent alongside your merchant
 * public key (x-auth-token) on every request.
 *
 * The payout endpoint requires the JSON body to be 3DES-encrypted
 * first and sent as `{ "message": "<base64>" }` — see encrypt3DES
 * below, confirmed against Klasha's own documented algorithm sample.
 * One correction applied versus the original sample shared for this
 * project: the encryption key MUST be *exactly* 24 characters, not
 * "at least" 24 — a shorter or longer key silently produces
 * ciphertext Klasha's backend can't decrypt, which was the original
 * bug reported ("your encryption key string is not 24 characters
 * length").
 */

/**
 * DES-EDE3-CBC (triple DES) encryption, matching Klasha's documented
 * algorithm exactly. `encryptionKey` must be exactly 24 characters —
 * Klasha issues this from the dashboard alongside your API keys.
 */
function encrypt3DES(payload, encryptionKey) {
  if (!encryptionKey || encryptionKey.length !== 24) {
    throw new Error(
      `Klasha encryption key must be exactly 24 characters long (got ${encryptionKey ? encryptionKey.length : 0}). ` +
        'Find it on the Klasha dashboard under Settings -> Generate API Keys.'
    );
  }

  const key = Buffer.from(encryptionKey, 'utf8');
  const iv = key.subarray(0, 8);

  const cipher = crypto.createCipheriv('des-ede3-cbc', key, iv);
  let encrypted = cipher.update(
    typeof payload === 'string' ? payload : JSON.stringify(payload),
    'utf8',
    'base64'
  );
  encrypted += cipher.final('base64');
  return encrypted;
}

class KlashaClient {
  constructor({ baseUrl, publicKey, secretKey, encryptionKey, businessId }) {
    this.baseUrl = baseUrl || 'https://api.klasha.com';
    this.publicKey = publicKey;
    this.secretKey = secretKey;
    this.encryptionKey = encryptionKey;
    this.businessId = businessId;
    this._token = null;
    this._tokenExpiresAt = 0;
    this._tokenTtlMs = 20 * 60 * 1000;
  }

  async _getToken() {
    const now = Date.now();
    if (this._token && now < this._tokenExpiresAt) return this._token;

    if (!this.publicKey || !this.secretKey) {
      throw new Error('KLASHA_PUBLIC_KEY / KLASHA_SECRET_KEY are not set. Add them to .env.');
    }

    const response = await axios.post(
      `${this.baseUrl}/auth/account/v2/login`,
      {
        publicKey: this.publicKey,
        secretKey: this.secretKey,
      },
      { httpsAgent: proxyAgent, proxy: false }
    );

    const token = response.data?.token || response.data?.data?.token;
    if (!token) throw new Error('Klasha did not return a token. Check your credentials.');

    this._token = token;
    this._tokenExpiresAt = now + this._tokenTtlMs;
    return token;
  }

  async _headers() {
    const token = await this._getToken();
    return {
      'Content-Type': 'application/json',
      'x-auth-token': this.publicKey,
      Authorization: `Bearer ${token}`,
    };
  }

  async get(path, params) {
    const headers = await this._headers();
    try {
      const response = await axios.get(`${this.baseUrl}${path}`, {
        params,
        headers,
        timeout: 20000,
        httpsAgent: proxyAgent,
        proxy: false,
      });
      return response.data;
    } catch (err) {
      throw this._normalize(err);
    }
  }

  /**
   * Plain (unencrypted) POST — used for endpoints that don't require
   * the 3DES payload wrapping, like resolve-account.
   */
  async post(path, data) {
    const headers = await this._headers();
    try {
      const response = await axios.post(`${this.baseUrl}${path}`, data, {
        headers,
        timeout: 20000,
        httpsAgent: proxyAgent,
        proxy: false,
      });
      return response.data;
    } catch (err) {
      throw this._normalize(err);
    }
  }

  /**
   * Encrypted POST — for every "(new encryption)" endpoint (payouts,
   * virtual account creation). Wraps `data` per encrypt3DES and sends
   * `{ message: "<base64>" }` as the body, exactly as Klasha's docs
   * and their team's own sample specify.
   */
  async postEncrypted(path, data, extraParams) {
    const headers = await this._headers();
    const message = encrypt3DES(data, this.encryptionKey);
    try {
      const response = await axios.post(
        `${this.baseUrl}${path}`,
        { message },
        { headers, params: extraParams, timeout: 20000, httpsAgent: proxyAgent, proxy: false }
      );
      return response.data;
    } catch (err) {
      throw this._normalize(err);
    }
  }

  /**
   * The one confirmed payout path, with your businessId substituted
   * in — see corridors.js's KLASHA_PAYOUT_PATH_TEMPLATE for where
   * this shape comes from (https://developers.klasha.com/transfers/payout).
   */
  payoutPath() {
    if (!this.businessId) {
      throw new Error('KLASHA_BUSINESS_ID is not set. Add it to .env — find it on the Klasha dashboard.');
    }
    return `/wallet/merchant/${this.businessId}/bank/transfer/v2/request`;
  }

  _normalize(err) {
    const status = err.response?.status;
    const message =
      err.response?.data?.message ||
      err.response?.data?.error ||
      err.message ||
      'Klasha request failed';
    const normalized = new Error(message);
    normalized.status = status || 502;
    normalized.details = err.response?.data;
    return normalized;
  }
}

const klasha = new KlashaClient({
  baseUrl: process.env.KLASHA_BASE_URL,
  publicKey: process.env.KLASHA_PUBLIC_KEY,
  secretKey: process.env.KLASHA_SECRET_KEY,
  encryptionKey: process.env.KLASHA_ENCRYPTION_KEY,
  businessId: process.env.KLASHA_BUSINESS_ID,
});

module.exports = { KlashaClient, klasha, encrypt3DES };

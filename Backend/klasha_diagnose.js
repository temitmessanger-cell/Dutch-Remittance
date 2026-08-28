// Klasha isolation diagnostic — run with:  node klasha_diagnose.js
// Reads the SAME env vars your app uses. Tests each layer separately
// so you know exactly which one fails. No money moves — it only tests
// auth + a read call. Paste the full output back.

require('dotenv').config();
const axios = require('axios');
const crypto = require('crypto');
const { HttpsProxyAgent } = require('https-proxy-agent');

const baseUrl = process.env.KLASHA_BASE_URL || 'https://gate.klasapps.com';
const publicKey = process.env.KLASHA_PUBLIC_KEY;
const secretKey = process.env.KLASHA_SECRET_KEY;
const encryptionKey = process.env.KLASHA_ENCRYPTION_KEY;
const businessId = process.env.KLASHA_BUSINESS_ID;
const proxyUrl = process.env.OUTBOUND_PROXY_URL;
const proxyAgent = proxyUrl ? new HttpsProxyAgent(proxyUrl) : undefined;

function mask(v) {
  if (!v) return '(NOT SET)';
  return v.length <= 6 ? '***' : v.slice(0, 3) + '...' + v.slice(-2) + ` (len ${v.length})`;
}

(async () => {
  console.log('==== KLASHA DIAGNOSTIC ====\n');

  // ---- Layer 0: config presence ----
  console.log('--- Config (values masked) ---');
  console.log('KLASHA_BASE_URL      :', baseUrl);
  console.log('KLASHA_PUBLIC_KEY    :', mask(publicKey));
  console.log('KLASHA_SECRET_KEY    :', mask(secretKey));
  console.log('KLASHA_ENCRYPTION_KEY:', mask(encryptionKey));
  console.log('KLASHA_BUSINESS_ID   :', mask(businessId));
  console.log('OUTBOUND_PROXY_URL   :', proxyUrl ? 'SET (via proxy)' : '(NOT SET — direct)');
  console.log('');

  // ---- Layer 1: encryption key length (fails fast, no network) ----
  console.log('--- Layer 1: encryption key length ---');
  const keyLen = encryptionKey ? Buffer.from(encryptionKey, 'utf8').length : 0;
  if (keyLen < 24) {
    console.log(`FAIL: key is ${keyLen} bytes, must be >= 24. This blocks payouts/virtual-account.`);
  } else {
    console.log(`OK: key is ${keyLen} bytes (>= 24).`);
  }
  console.log('');

  // ---- Layer 2: outbound IP (what Klasha sees) ----
  console.log('--- Layer 2: outbound IP (whitelist check) ---');
  try {
    const ipres = await axios.get('https://api.ipify.org?format=json', {
      httpsAgent: proxyAgent, proxy: false, timeout: 15000,
    });
    console.log('Outbound IP Klasha will see:', ipres.data.ip);
    console.log('-> This IP must be whitelisted in your Klasha dashboard if Klasha requires it.');
  } catch (e) {
    console.log('Could not determine outbound IP:', e.message);
  }
  console.log('');

  // ---- Layer 3: auth/login ----
  console.log('--- Layer 3: Klasha auth (POST /auth/account/v2/login) ---');
  let token = null;
  try {
    const res = await axios.post(
      `${baseUrl}/auth/account/v2/login`,
      { publicKey, secretKey },
      { httpsAgent: proxyAgent, proxy: false, timeout: 20000 }
    );
    token = res.data?.token || res.data?.data?.token;
    console.log('HTTP status:', res.status);
    if (token) {
      console.log('OK: token received (auth works).');
    } else {
      console.log('FAIL: 200 but NO token in response. Body:');
      console.log(JSON.stringify(res.data, null, 2).slice(0, 800));
    }
  } catch (e) {
    console.log('FAIL: auth request errored.');
    console.log('  HTTP status :', e.response?.status);
    console.log('  Message     :', e.response?.data?.message || e.message);
    console.log('  Body        :', JSON.stringify(e.response?.data || {}, null, 2).slice(0, 800));
    console.log('\n-> Auth is the blocker. Stop here and fix this first.');
    return;
  }
  console.log('');

  // ---- Layer 4: an authenticated read call ----
  console.log('--- Layer 4: authenticated read (banks list) ---');
  try {
    const res = await axios.get(`${baseUrl}/misc/banks/NGN`, {
      headers: {
        'Content-Type': 'application/json',
        'x-auth-token': publicKey,
        Authorization: `Bearer ${token}`,
      },
      httpsAgent: proxyAgent, proxy: false, timeout: 20000,
    });
    console.log('HTTP status:', res.status, '- OK: authenticated calls work.');
  } catch (e) {
    console.log('Authenticated read failed (endpoint may differ, but auth reached Klasha):');
    console.log('  HTTP status :', e.response?.status);
    console.log('  Message     :', e.response?.data?.message || e.message);
  }

  console.log('\n==== END ====');
})();

const CLIENT_ID = 'oauth2client_0000B76HfwlJAyl5AuaLeW';
const CLIENT_SECRET = 'mnzpub.TgOFP7KKTWqF92m0xhEEKge0tEwDp2eTYAQE9Durar/mb8ZRDGtYKjhpIU1Nd8WHlALN+yQ4XDJsR/A/Hj5tJw==';
const REDIRECT_URI = 'https://proline-crm.pages.dev';

const KEYS = {
  accessToken: 'monzo_access_token',
  refreshToken: 'monzo_refresh_token',
  expiry: 'monzo_token_expiry',
  state: 'monzo_oauth_state',
};

export function getStoredToken() {
  return localStorage.getItem(KEYS.accessToken) ?? '';
}

export function getTokenExpiry() {
  const v = localStorage.getItem(KEYS.expiry);
  return v ? new Date(v) : null;
}

export function isTokenExpired() {
  const expiry = getTokenExpiry();
  if (!expiry) return true;
  return expiry.getTime() - Date.now() < 60_000; // treat as expired if < 1 min left
}

export function isConnected() {
  return !!localStorage.getItem(KEYS.accessToken);
}

function storeTokens(access: string, refresh: string, expiresIn: number) {
  localStorage.setItem(KEYS.accessToken, access);
  localStorage.setItem(KEYS.refreshToken, refresh);
  const expiry = new Date(Date.now() + expiresIn * 1000);
  localStorage.setItem(KEYS.expiry, expiry.toISOString());
}

export function disconnect() {
  localStorage.removeItem(KEYS.accessToken);
  localStorage.removeItem(KEYS.refreshToken);
  localStorage.removeItem(KEYS.expiry);
  localStorage.removeItem(KEYS.state);
}

export function startOAuthFlow() {
  const state = crypto.randomUUID();
  localStorage.setItem(KEYS.state, state);
  const url = new URL('https://auth.monzo.com/');
  url.searchParams.set('client_id', CLIENT_ID);
  url.searchParams.set('redirect_uri', REDIRECT_URI);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('state', state);
  window.location.href = url.toString();
}

// Returns true if we handled a callback, false otherwise
export async function handleOAuthCallback(): Promise<boolean> {
  const params = new URLSearchParams(window.location.search);
  const code = params.get('code');
  const state = params.get('state');
  if (!code) return false;

  // Validate state — use localStorage so it survives the magic-link cross-tab redirect
  const storedState = localStorage.getItem(KEYS.state);
  localStorage.removeItem(KEYS.state);
  if (state && storedState && state !== storedState) {
    console.error('Monzo OAuth state mismatch');
    return false;
  }

  const ok = await exchangeCode(code);
  window.history.replaceState({}, '', window.location.pathname);
  return ok;
}

async function exchangeCode(code: string): Promise<boolean> {
  try {
    const res = await fetch('https://api.monzo.com/oauth2/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        client_id: CLIENT_ID,
        client_secret: CLIENT_SECRET,
        redirect_uri: REDIRECT_URI,
        code,
      }),
    });
    if (!res.ok) { console.error('Monzo token exchange failed', await res.text()); return false; }
    const data = await res.json();
    storeTokens(data.access_token, data.refresh_token, data.expires_in ?? 3600);
    return true;
  } catch (e) {
    console.error('Monzo exchange error', e);
    return false;
  }
}

export async function refreshAccessToken(): Promise<boolean> {
  const refreshToken = localStorage.getItem(KEYS.refreshToken);
  if (!refreshToken) return false;
  try {
    const res = await fetch('https://api.monzo.com/oauth2/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        client_id: CLIENT_ID,
        client_secret: CLIENT_SECRET,
        refresh_token: refreshToken,
      }),
    });
    if (!res.ok) { disconnect(); return false; }
    const data = await res.json();
    storeTokens(data.access_token, data.refresh_token, data.expires_in ?? 3600);
    return true;
  } catch {
    return false;
  }
}

// Call this before any API request — silently refreshes if needed
export async function getValidToken(): Promise<string> {
  if (isTokenExpired()) {
    await refreshAccessToken();
  }
  return getStoredToken();
}

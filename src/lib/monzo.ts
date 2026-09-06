// Monzo OAuth is deliberately disabled until it is moved behind an approved,
// authenticated server-side gateway. Never put a Monzo client secret or refresh
// token in browser JavaScript or localStorage.

const LEGACY_KEYS = ['monzo_access_token', 'monzo_refresh_token', 'monzo_token_expiry', 'monzo_oauth_state'];

export function getStoredToken() { return ''; }
export function getTokenExpiry(): Date | null { return null; }
export function isTokenExpired() { return true; }
export function isConnected() { return false; }

export function disconnect() {
  for (const key of LEGACY_KEYS) localStorage.removeItem(key);
}

export function startOAuthFlow() {
  window.alert('Monzo connection is temporarily disabled while banking access is moved to a secure server-side integration.');
}

export async function handleOAuthCallback(): Promise<boolean> {
  const params = new URLSearchParams(window.location.search);
  if (!params.has('code')) return false;
  window.history.replaceState({}, '', window.location.pathname);
  return false;
}

export async function refreshAccessToken(): Promise<boolean> { return false; }
export async function getValidToken(): Promise<string> { return ''; }

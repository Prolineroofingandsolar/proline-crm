const CLIENT_ID = '845292341174-dqqb7o1dcsvf2brs7cbglmaop8k50d4q.apps.googleusercontent.com';
const SCOPE = 'https://www.googleapis.com/auth/gmail.send';

let accessToken: string | null = null;

declare namespace google.accounts.oauth2 {
  interface TokenClient {
    requestAccessToken(options?: { prompt?: string }): void;
  }
  interface TokenResponse {
    access_token: string;
    error?: string;
  }
  function initTokenClient(config: {
    client_id: string;
    scope: string;
    callback: (resp: TokenResponse) => void;
    error_callback?: (err: { type: string }) => void;
  }): TokenClient;
}

function waitForGoogleScript(timeoutMs = 10000): Promise<void> {
  return new Promise((resolve, reject) => {
    if (typeof google !== 'undefined' && google?.accounts?.oauth2) {
      resolve(); return;
    }
    const start = Date.now();
    const check = setInterval(() => {
      if (typeof google !== 'undefined' && google?.accounts?.oauth2) {
        clearInterval(check); resolve();
      } else if (Date.now() - start > timeoutMs) {
        clearInterval(check);
        reject(new Error('Google sign-in script failed to load. Check your internet connection and try again.'));
      }
    }, 100);
  });
}

async function getAccessToken(): Promise<string> {
  if (accessToken) return accessToken;

  await waitForGoogleScript();

  return new Promise((resolve, reject) => {
    const client = google.accounts.oauth2.initTokenClient({
      client_id: CLIENT_ID,
      scope: SCOPE,
      callback: (resp) => {
        if (resp.error || !resp.access_token) {
          reject(new Error(resp.error ?? 'No access token returned'));
          return;
        }
        accessToken = resp.access_token;
        setTimeout(() => { accessToken = null; }, 55 * 60 * 1000);
        resolve(accessToken);
      },
      error_callback: (err) => {
        if (err.type === 'popup_closed') {
          reject(new Error('Sign-in popup was closed — please try again'));
        } else if (err.type === 'popup_blocked') {
          reject(new Error('Popup was blocked — allow popups for this site and try again'));
        } else {
          reject(new Error(`Sign-in failed: ${err.type}`));
        }
      },
    });

    // Always show the account picker so the user can see what's happening
    client.requestAccessToken({ prompt: 'select_account' });
  });
}

function toBase64Url(str: string): string {
  return btoa(unescape(encodeURIComponent(str)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function buildRfc2822(to: string, subject: string, body: string): string {
  return [
    `To: ${to}`,
    `Subject: ${subject}`,
    `Content-Type: text/plain; charset=utf-8`,
    ``,
    body,
  ].join('\r\n');
}

export async function sendGmail(to: string, subject: string, body: string): Promise<void> {
  const token = await getAccessToken();

  const raw = toBase64Url(buildRfc2822(to, subject, body));

  const res = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ raw }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    if (res.status === 401) accessToken = null;
    throw new Error((err as { error?: { message?: string } }).error?.message ?? 'Failed to send — please try again');
  }
}

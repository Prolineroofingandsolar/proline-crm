const CLIENT_ID = '845292341174-dqqb7o1dcsvf2brs7cbglmaop8k50d4q.apps.googleusercontent.com';
const SCOPE = 'https://www.googleapis.com/auth/gmail.send';

let accessToken: string | null = null;
let tokenClient: google.accounts.oauth2.TokenClient | null = null;

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

export function isGmailReady(): boolean {
  return !!accessToken;
}

function getTokenClient(): Promise<string> {
  return new Promise((resolve, reject) => {
    if (accessToken) { resolve(accessToken); return; }

    if (!tokenClient) {
      tokenClient = google.accounts.oauth2.initTokenClient({
        client_id: CLIENT_ID,
        scope: SCOPE,
        callback: (resp) => {
          if (resp.error) { reject(new Error(resp.error)); return; }
          accessToken = resp.access_token;
          // Tokens last ~1 hour — clear so next send re-auths if needed
          setTimeout(() => { accessToken = null; }, 55 * 60 * 1000);
          resolve(accessToken);
        },
        error_callback: (err) => reject(new Error(err.type)),
      });
    }

    tokenClient.requestAccessToken({ prompt: '' });
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
  const token = await getTokenClient();

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
    // Token may have expired mid-session — clear it so next attempt re-auths
    if (res.status === 401) accessToken = null;
    throw new Error((err as { error?: { message?: string } }).error?.message ?? 'Failed to send email');
  }
}

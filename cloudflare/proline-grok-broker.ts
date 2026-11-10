import OAuthProvider, { AuthorizationError, type OAuthHelpers } from './vendor/workers-oauth-provider/src/oauth-provider';
import { createAssertion } from '../supabase/functions/proline-grok-mcp/broker-auth.mjs';

// Independent OAuth issuer. Supabase checks the user only during consent and
// the MCP service checks the profile on every call; no Supabase refresh token
// is stored by this broker or sent to Grok.
const ORIGIN = 'https://proline-grok-mcp.royal-art-964b.workers.dev';
const SUPABASE = 'https://qzvdzzvkocmulcfujyea.supabase.co';
const RESOURCE = `${ORIGIN}/mcp`;
interface Env {
  OAUTH_PROVIDER: OAuthHelpers;
  SUPABASE_ANON_KEY: string;
  PROLINE_GROK_BROKER_SECRET: string;
}
interface ApiContext {
  props?: { userId?: string };
  auth?: { scope?: string[] };
}

const escape = (value: unknown) => String(value ?? '').replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);

export async function verifyLogin(email: string, password: string, anonKey: string) {
  const login = await fetch(`${SUPABASE}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: anonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  if (!login.ok) return null;
  const session = await login.json() as { access_token?: string; user?: { id?: string } };
  if (!session.access_token || !session.user?.id) return null;
  // Ask Auth for the current user, as Supabase's MFA listFactors implementation
  // does. Password-only consent must never bypass an enrolled second factor.
  const currentUser = await fetch(`${SUPABASE}/auth/v1/user`, {
    headers: { apikey: anonKey, Authorization: `Bearer ${session.access_token}` },
  });
  if (!currentUser.ok) throw new Error('Authentication service unavailable');
  const verified = await currentUser.json() as { id?: string; factors?: { status?: string }[] };
  if (verified.id !== session.user.id || (Array.isArray(verified.factors) && verified.factors.some(factor => factor.status === 'verified'))) return null;
  const profile = await fetch(`${SUPABASE}/rest/v1/profiles?id=eq.${encodeURIComponent(session.user.id)}&select=id,role,active,organisation_id`, {
    headers: { apikey: anonKey, Authorization: `Bearer ${session.access_token}` },
  });
  if (!profile.ok) throw new Error('Profile service unavailable');
  const rows = await profile.json() as { id?: string; role?: string; active?: boolean; organisation_id?: string }[];
  const person = Array.isArray(rows) ? rows[0] : null;
  return person?.id === session.user.id && person?.active === true && person?.role === 'admin' && person?.organisation_id ? person.id : null;
}

const defaultHandler = {
  async fetch(request: Request, env: Env) {
    const url = new URL(request.url);
    if (url.pathname !== '/authorize') return new Response('Not found', { status: 404 });
    try {
      if (request.method === 'GET') {
        const auth = await env.OAUTH_PROVIDER.parseAuthRequest(request);
        const details = await env.OAUTH_PROVIDER.describeConsent(auth);
        const consent = await env.OAUTH_PROVIDER.beginConsent(auth);
        const scopes = details.scope.map((scope: string) => `<input type="hidden" name="scope" value="${escape(scope)}">`).join('');
        consent.headers.set('Content-Type', 'text/html; charset=utf-8');
        consent.headers.set('Cache-Control', 'no-store');
        return new Response(`<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Connect ProLine CRM</title></head><body><main><h1>Connect ProLine CRM</h1><p><strong>${escape(details.clientName)}</strong> requests access to your CRM. The authorisation returns to <strong>${escape(details.redirectHost)}</strong>.</p><p>Permissions: ${details.scope.map(escape).join(', ')}. Existing CRM permissions apply.</p><form method="post" action="/authorize"><input type="hidden" name="handle" value="${escape(consent.handle)}">${scopes}<label>Administrator email <input type="email" name="email" autocomplete="username" required></label><br><label>Password <input type="password" name="password" autocomplete="current-password" required></label><br><button name="decision" value="approve">Sign in and allow</button><button name="decision" value="deny" formnovalidate>Deny</button></form></main></body></html>`, { headers: consent.headers });
      }
      if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
      const form = await request.formData();
      const handle = String(form.get('handle') || '');
      if (form.get('decision') !== 'approve') {
        const denied = await env.OAUTH_PROVIDER.denyConsent(request, handle);
        return new Response(null, { status: 302, headers: denied.headers });
      }
      const userId = await verifyLogin(String(form.get('email') || ''), String(form.get('password') || ''), env.SUPABASE_ANON_KEY);
      if (!userId) return new Response('Sign-in failed, or this account is not an active administrator. Start the connection again.', { status: 403 });
      const approved = await env.OAUTH_PROVIDER.approveConsent(request, handle, { scope: form.getAll('scope').map(String) });
      const result = await env.OAUTH_PROVIDER.completeAuthorization({ request: approved.request, userId, scope: approved.request.scope, metadata: {}, props: { userId } });
      approved.headers.set('Location', result.redirectTo);
      return new Response(null, { status: 302, headers: approved.headers });
    } catch (error) {
      if (error instanceof AuthorizationError && error.redirectTo) return Response.redirect(error.redirectTo, 302);
      return new Response('Unable to complete sign-in. Start the connection again.', { status: 400, headers: { 'Cache-Control': 'no-store' } });
    }
  },
};

const apiHandler = {
  async fetch(request: Request, env: Env, ctx: ApiContext) {
    if (new URL(request.url).pathname !== '/mcp') return new Response('Not found', { status: 404 });
    if (!ctx.props?.userId || !Array.isArray(ctx.auth?.scope) || !ctx.auth.scope.includes('profile')) return new Response('Forbidden', { status: 403 });
    const body = await request.arrayBuffer();
    if (body.byteLength > 1_000_000) return new Response('Request too large', { status: 413 });
    const assertion = await createAssertion({ secret: env.PROLINE_GROK_BROKER_SECRET, userId: ctx.props.userId, method: request.method, body });
    // Keep Supabase's gateway JWT verification enabled. The public anon key
    // passes the gateway only; the function independently requires the signed,
    // single-use broker assertion before granting access to any CRM data.
    const headers = new Headers({ Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`, apikey: env.SUPABASE_ANON_KEY, 'x-proline-broker-assertion': assertion });
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', body));
    headers.set('x-proline-body-digest', Array.from(digest, byte => byte.toString(16).padStart(2, '0')).join(''));
    for (const name of ['accept', 'content-type', 'mcp-protocol-version']) {
      const value = request.headers.get(name); if (value) headers.set(name, value);
    }
    try {
      return await fetch(`${SUPABASE}/functions/v1/proline-grok-mcp/mcp`, { method: request.method, headers, body: ['GET', 'HEAD'].includes(request.method) ? undefined : body, signal: AbortSignal.timeout(15_000) });
    } catch {
      return Response.json({ error: 'temporarily_unavailable' }, { status: 503, headers: { 'Retry-After': '5' } });
    }
  },
};

export default new OAuthProvider({
  apiRoute: '/mcp', apiHandler, defaultHandler,
  authorizeEndpoint: '/authorize', tokenEndpoint: '/token', clientRegistrationEndpoint: '/register',
  scopesSupported: ['email', 'profile', 'offline_access'], requiredScopes: ['profile'],
  resourceMetadata: { resource: RESOURCE, authorization_servers: [ORIGIN], resource_name: 'ProLine CRM' },
  accessTokenTTL: 3600, refreshTokenTTL: undefined, clientRegistrationTTL: undefined,
});

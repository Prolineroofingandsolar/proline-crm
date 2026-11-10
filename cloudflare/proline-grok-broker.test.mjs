import test from 'node:test';
import assert from 'node:assert/strict';
import { rolldown } from 'rolldown';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

class MemoryKV {
  values = new Map();
  async get(k, options) { const value = this.values.get(k); if (value == null) return null; return options?.type === 'json' || options === 'json' ? JSON.parse(value) : value; }
  async put(k, value) { this.values.set(k, typeof value === 'string' ? value : String(value)); }
  async delete(k) { this.values.delete(k); }
  async list({ prefix = '' } = {}) { return { keys: [...this.values.keys()].filter(k => k.startsWith(prefix)).map(name => ({ name })), list_complete: true, cacheStatus: null }; }
}

test('OAuth broker signs in, calls CRM, refreshes without login, and rejects forged requests', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'grok-broker-test-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const file = join(dir, 'worker.mjs');
  const bundle = await rolldown({ input: 'cloudflare/proline-grok-broker.ts', external: ['cloudflare:workers'] });
  await bundle.write({ file, format: 'esm' }); await bundle.close();
  const js = await readFile(file, 'utf8');
  await writeFile(file, js.replace('import { WorkerEntrypoint } from "cloudflare:workers";', 'class WorkerEntrypoint {}'));
  const broker = await import(pathToFileURL(file).href);
  const worker = broker.default;
  const env = { OAUTH_KV: new MemoryKV(), SUPABASE_ANON_KEY: 'fake-anon', PROLINE_GROK_BROKER_SECRET: 'fake-secret-'.repeat(4) };
  const ctx = () => ({ waitUntil() {}, passThroughOnException() {} });
  const origin = 'https://proline-grok-mcp.royal-art-964b.workers.dev';
  const send = (path, options = {}) => worker.fetch(new Request(origin + path, options), env, ctx());
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  let loginScenario = 'admin';
  globalThis.fetch = async (url, options = {}) => {
    const target = String(url);
    if (target.includes('/auth/v1/token')) return Response.json({ access_token: 'test', user: { id: '12345678-1234-1234-1234-123456789abc', factors: loginScenario === 'mfa' ? [{ status: 'verified' }] : [] } });
    if (target.includes('/auth/v1/user')) return Response.json({ id: '12345678-1234-1234-1234-123456789abc', factors: loginScenario === 'mfa' ? [{ status: 'verified' }] : [] });
    if (target.includes('/rest/v1/profiles')) return Response.json([{ id: '12345678-1234-1234-1234-123456789abc', active: loginScenario !== 'inactive', role: loginScenario === 'employee' ? 'staff' : 'admin', organisation_id: 'org-1' }]);
    if (target.includes('/functions/v1/proline-grok-mcp/mcp')) {
      assert.match(options.headers.get('x-proline-broker-assertion'), /^[^.]+\.\d+\.[^.]+\.[a-f0-9]{64}$/);
      return Response.json({ jsonrpc: '2.0', id: 1, result: { connected: true } });
    }
    throw Error(`Unexpected upstream ${target}`);
  };
  for (const scenario of ['mfa', 'inactive', 'employee']) {
    loginScenario = scenario;
    assert.equal(await broker.verifyLogin('test@example.com', 'test-only', env.SUPABASE_ANON_KEY), null, `${scenario} must not receive a grant`);
  }
  loginScenario = 'admin';
  const challenge = await send('/mcp');
  assert.equal(challenge.status, 401);
  const register = await send('/register', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ client_name: 'Test agent', redirect_uris: ['https://example.com/callback'], token_endpoint_auth_method: 'none', grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'] }) });
  assert.equal(register.status, 201, await register.clone().text());
  const client = await register.json();
  const verifier = 'v'.repeat(64);
  const hashed = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
  const codeChallenge = Buffer.from(hashed).toString('base64url');
  const query = new URLSearchParams({ response_type: 'code', client_id: client.client_id, redirect_uri: 'https://example.com/callback', scope: 'email profile offline_access', resource: origin + '/mcp', code_challenge: codeChallenge, code_challenge_method: 'S256', state: 'test-state' });
  const consent = await send('/authorize?' + query);
  assert.equal(consent.status, 200, await consent.clone().text());
  const cookie = consent.headers.get('set-cookie').split(';')[0];
  const html = await consent.text();
  const handle = html.match(/name="handle" value="([^"]+)"/)[1];
  const form = new URLSearchParams({ handle, email: 'test@example.com', password: 'test-only', decision: 'approve' });
  for (const scope of ['email', 'profile', 'offline_access']) form.append('scope', scope);
  const approved = await send('/authorize', { method: 'POST', headers: { Cookie: cookie, 'Content-Type': 'application/x-www-form-urlencoded' }, body: form });
  assert.equal(approved.status, 302, await approved.clone().text());
  const code = new URL(approved.headers.get('location')).searchParams.get('code');
  assert.ok(code);
  const exchange = values => send('/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(values) });
  const tokenResponse = await exchange({ grant_type: 'authorization_code', code, redirect_uri: 'https://example.com/callback', client_id: client.client_id, code_verifier: verifier, resource: origin + '/mcp' });
  assert.equal(tokenResponse.status, 200, await tokenResponse.clone().text());
  const first = await tokenResponse.json(); assert.ok(first.refresh_token);
  const call = token => send('/mcp', { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' });
  assert.equal((await call('invalid')).status, 401);
  assert.equal((await call(first.access_token)).status, 200);
  const originalNow = Date.now;
  t.after(() => { Date.now = originalNow; });
  Date.now = () => originalNow() + 3_601_000;
  assert.equal((await call(first.access_token)).status, 401, 'expired token must be rejected before refresh');
  const renewedResponse = await exchange({ grant_type: 'refresh_token', refresh_token: first.refresh_token, client_id: client.client_id, resource: origin + '/mcp' });
  assert.equal(renewedResponse.status, 200, await renewedResponse.clone().text());
  const renewed = await renewedResponse.json();
  assert.ok(renewed.access_token); assert.equal((await call(renewed.access_token)).status, 200);
  assert.ok(renewed.refresh_token);
  Date.now = () => originalNow() + 7_202_000;
  assert.equal((await call(renewed.access_token)).status, 401);
  const secondResponse = await exchange({ grant_type: 'refresh_token', refresh_token: renewed.refresh_token, client_id: client.client_id, resource: origin + '/mcp' });
  assert.equal(secondResponse.status, 200, await secondResponse.clone().text());
  const second = await secondResponse.json();
  assert.ok(second.refresh_token);
  assert.equal((await call(second.access_token)).status, 200);
});

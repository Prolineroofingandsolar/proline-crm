import test from 'node:test';
import assert from 'node:assert/strict';
import { ConnectionFailure, createMcpHandler, proxyOAuth } from './http.mjs';

const baseUrl = 'https://project.supabase.co/functions/v1/proline-mcp';
const issuer = 'https://oauth.example.com';
const resource = `${baseUrl}/mcp`;
const tools = [{ name: 'proline_status', inputSchema: { type: 'object' } }];
function handler(overrides = {}) {
  return createMcpHandler({ baseUrl, authorizationServer: issuer, scopes: ['email', 'profile'], tools,
    authenticate: async (request) => request.headers.get('authorization') === 'Bearer valid' ? { organisation: 'org-1' } : null,
    callTool: async (_, __, auth) => ({ connected: true, organisation: auth.organisation }),
    asToolResult: (value, isError = false) => ({ content: [{ type: 'text', text: JSON.stringify(value) }], isError }),
    instructions: 'Existing scoped tools', ...overrides });
}
const rpc = (method, params = {}, token = 'valid', extra = {}) => new Request(resource, {
  method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, ...extra },
  body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
});

test('GET and POST both discover the same stable authorization server before sign-in', async () => {
  const serve = handler();
  for (const method of ['GET', 'POST']) {
    const response = await serve(new Request(`${resource}?v=6`, { method }));
    assert.equal(response.status, 401);
    const challenge = response.headers.get('www-authenticate');
    assert.ok(!challenge.includes('invalid_token'), 'missing credentials are not an expired grant');
    const metadata = challenge.match(/resource_metadata="([^"]+)"/)[1];
    const details = await (await serve(new Request(metadata))).json();
    assert.equal(details.resource, resource);
    assert.deepEqual(details.authorization_servers, [issuer]);
    assert.ok(!details.scopes_supported.includes('offline_access'));
  }
  const mirror = await serve(new Request(`${baseUrl}/oauth/.well-known/oauth-authorization-server`));
  assert.equal(mirror.status, 307);
  assert.equal(mirror.headers.get('location'), `${issuer}/.well-known/oauth-authorization-server`);
});

test('expired access is challenged, denied roles are forbidden, outages never discard a grant', async () => {
  assert.equal((await handler()(rpc('ping', {}, 'expired'))).status, 401);
  const denied = await handler({ authenticate: async () => { throw new ConnectionFailure(403, 'admin_required'); } })(rpc('ping'));
  assert.equal(denied.status, 403);
  for (const failure of [new ConnectionFailure(503, 'auth_unavailable'), new TypeError('network unavailable')]) {
    const response = await handler({ authenticate: async () => { throw failure; } })(rpc('ping'));
    assert.equal(response.status, 503);
    assert.equal(response.headers.get('www-authenticate'), null);
    assert.equal(response.headers.get('retry-after'), '5');
  }
});

test('Supabase runtime path rewriting retains authentication and the public resource identity', async () => {
  const serve = handler();
  for (const pathname of ['/functions/v1/proline-mcp/mcp', '/proline-mcp/mcp', '/mcp']) {
    const response = await serve(new Request(`http://edge-runtime${pathname}`));
    assert.equal(response.status, 401);
    assert.ok(response.headers.get('www-authenticate').includes(`${baseUrl}/.well-known/oauth-protected-resource`));
  }
  assert.equal((await serve(new Request('http://edge-runtime/unrelated/mcp'))).status, 404);
});

test('negotiates supported protocol versions and retains the existing tool catalogue', async () => {
  const serve = handler();
  for (const version of ['2024-11-05', '2025-03-26', '2025-06-18']) {
    const response = await serve(rpc('initialize', { protocolVersion: version }));
    assert.equal((await response.json()).result.protocolVersion, version);
  }
  assert.deepEqual((await (await serve(rpc('tools/list'))).json()).result.tools, tools);
  assert.equal((await serve(new Request(resource, { headers: { Authorization: 'Bearer valid' } }))).status, 405);
  assert.equal((await serve(rpc('ping', {}, 'valid', { 'MCP-Protocol-Version': 'unsupported' }))).status, 400);
  assert.equal((await serve(new Request(resource, { method: 'POST', headers: { Authorization: 'Bearer valid' }, body: '{' }))).status, 400);
  assert.equal((await serve(new Request(resource, { method: 'POST', headers: { Authorization: 'Bearer valid' }, body: JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) }))).status, 202);
});

test('OAuth proxy preserves public client id, refresh rotation, expiry and confidential authentication', async () => {
  for (const authMethod of ['none', 'client_secret_basic', 'client_secret_post']) {
    const body = new URLSearchParams({ grant_type: 'refresh_token', refresh_token: 'refresh-1', client_id: 'client-1', resource });
    if (authMethod === 'client_secret_post') body.set('client_secret', 'test-secret');
    const headers = { 'Content-Type': 'application/x-www-form-urlencoded' };
    if (authMethod === 'client_secret_basic') headers.Authorization = `Basic ${btoa('client-1:test-secret')}`;
    const response = await proxyOAuth(new Request(`${issuer}/connect/complete`, { method: 'POST', headers, body }), 'https://project.supabase.co/auth/v1/oauth/token', async (url, init) => {
      assert.equal(url, 'https://project.supabase.co/auth/v1/oauth/token');
      assert.equal(init.redirect, 'manual');
      assert.equal(init.headers.get('authorization'), headers.Authorization ?? null);
      assert.equal(new TextDecoder().decode(init.body), body.toString());
      return Response.json({ access_token: 'access-2', refresh_token: 'refresh-2', token_type: 'bearer', expires_in: 3600 });
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { access_token: 'access-2', refresh_token: 'refresh-2', token_type: 'bearer', expires_in: 3600 });
    assert.equal(response.headers.get('cache-control'), 'no-store');
  }
});

test('full expired-token recovery rotates tokens twice without another sign-in', async () => {
  let generation = 1;
  let calls = 0;
  const serve = handler({ authenticate: async (request) => request.headers.get('authorization') === `Bearer access-${generation}` ? { organisation: 'org-1' } : null });
  let refreshToken = 'refresh-1';
  let accessToken = 'access-1';
  const upstream = async (_, init) => {
    calls++;
    const form = new URLSearchParams(new TextDecoder().decode(init.body));
    assert.equal(form.get('grant_type'), 'refresh_token');
    assert.equal(form.get('client_id'), 'client-1');
    assert.equal(form.get('refresh_token'), `refresh-${generation - 1}`);
    return Response.json({ access_token: `access-${generation}`, refresh_token: `refresh-${generation}`, token_type: 'bearer', expires_in: 3600 });
  };
  for (let run = 0; run < 2; run++) {
    generation++;
    assert.equal((await serve(rpc('tools/call', { name: 'proline_status' }, accessToken))).status, 401);
    const renewed = await proxyOAuth(new Request(`${issuer}/connect/complete`, { method: 'POST', body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: refreshToken, client_id: 'client-1' }), headers: { 'Content-Type': 'application/x-www-form-urlencoded' } }), 'https://project.supabase.co/auth/v1/oauth/token', upstream);
    ({ access_token: accessToken, refresh_token: refreshToken } = await renewed.json());
    const retried = await serve(rpc('tools/call', { name: 'proline_status' }, accessToken));
    assert.equal(retried.status, 200);
    const result = (await retried.json()).result;
    assert.equal(result.isError, false);
    assert.equal(JSON.parse(result.content[0].text).organisation, 'org-1');
  }
  assert.equal(calls, 2);
});

test('OAuth failures retain status, and HTML or network failures do not become invalid-token responses', async () => {
  const request = () => new Request(`${issuer}/token`, { method: 'POST', body: 'grant_type=refresh_token' });
  const rejected = await proxyOAuth(request(), 'https://upstream.test/token', async () => Response.json({ error: 'invalid_grant' }, { status: 400 }));
  assert.equal(rejected.status, 400);
  assert.equal((await rejected.json()).error, 'invalid_grant');
  for (const upstream of [async () => new Response('<html>challenge</html>', { status: 403 }), async () => { throw new Error('network'); }]) {
    const response = await proxyOAuth(request(), 'https://upstream.test/token', upstream);
    assert.equal(response.status, 503);
    assert.equal((await response.json()).error, 'temporarily_unavailable');
  }
});

test('public health explicitly distinguishes reachability from a tested account connection', async () => {
  const result = await (await handler()(new Request(`${baseUrl}/health`))).json();
  assert.equal(result.authentication_tested, false);
  assert.equal(result.connector_version, '0.5.0');
});

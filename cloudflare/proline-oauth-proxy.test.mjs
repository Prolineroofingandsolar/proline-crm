import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './proline-oauth-proxy.mjs';

const origin = 'https://oauth.prolineroofingandsolar.co.uk';

test('existing OAuth discovery, authorization and refresh aliases use the same provider', async (t) => {
  const discovery = await (await worker.fetch(new Request(`${origin}/.well-known/oauth-authorization-server`), {})).json();
  assert.equal(discovery.issuer, origin);
  assert.equal(discovery.token_endpoint, `${origin}/connect/complete`);
  assert.ok(discovery.grant_types_supported.includes('refresh_token'));
  assert.ok(discovery.token_endpoint_auth_methods_supported.includes('none'));
  assert.ok(discovery.scopes_supported.includes('offline_access'));
  const authorize = await worker.fetch(new Request(`${origin}/authorize?client_id=client-1&code_challenge=test&state=state-1`), {});
  const target = new URL(authorize.headers.get('location'));
  assert.equal(target.pathname, '/auth/v1/oauth/authorize');
  assert.equal(target.searchParams.get('code_challenge'), 'test');
  assert.equal(target.searchParams.get('state'), 'state-1');
  for (const path of ['/token', '/connect/complete', '/api/oauth/token']) {
    let attempts = 0;
    const fetchMock = t.mock.method(globalThis, 'fetch', async (url, init) => {
      attempts++;
      assert.equal(url, 'https://qzvdzzvkocmulcfujyea.supabase.co/auth/v1/oauth/token');
      const body = new URLSearchParams(new TextDecoder().decode(init.body));
      assert.equal(body.get('client_id'), 'public-client');
      assert.equal(body.get('refresh_token'), 'test-refresh');
      return Response.json({ access_token: 'new-access', refresh_token: 'new-refresh', expires_in: 3600, token_type: 'bearer' });
    });
    const log = t.mock.method(console, 'info', () => {});
    const response = await worker.fetch(new Request(`${origin}${path}`, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'refresh_token', client_id: 'public-client', refresh_token: 'test-refresh' }) }), {});
    assert.equal(response.status, 200);
    assert.equal((await response.json()).refresh_token, 'new-refresh');
    assert.equal(attempts, 1);
    const audit = log.mock.calls[0].arguments[0];
    assert.equal(JSON.parse(audit).grant_type, 'refresh_token');
    assert.ok(!audit.includes('test-refresh') && !audit.includes('new-refresh') && !audit.includes('new-access'));
    fetchMock.mock.restore();
    log.mock.restore();
  }
});

test('consent accurately describes existing internal tools without promising customer actions', async () => {
  const response = await worker.fetch(new Request(`${origin}/oauth/consent?authorization_id=test`), {});
  const page = await response.text();
  assert.ok(page.includes('add verified leads'));
  assert.ok(page.includes('send customer messages, make purchases, delete records'));
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

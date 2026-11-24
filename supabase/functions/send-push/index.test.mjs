import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';

const source = readFileSync(new URL('./index.ts', import.meta.url), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;

function createHandler({ apnsConfig = true, apnsStatus = 200, networkError = false } = {}) {
  let handler;
  const device = { id: 'device-1', device_token: 'secret-token', environment: 'development', bundle_id: 'crm' };
  const db = { from(table) {
    assert.equal(table, 'native_push_devices');
    const query = { select() { return this; }, eq() { return this; }, in() { return this; }, then(resolve) { return Promise.resolve({ data: [device], error: null }).then(resolve); } };
    return query;
  } };
  const settings = { SUPABASE_URL: 'https://example.test', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: 'service', ...(apnsConfig ? { APNS_KEY_ID: 'key', APNS_TEAM_ID: 'team', APNS_PRIVATE_KEY: 'private' } : {}) };
  const sandbox = {
    exports: {}, Response, Request, console: { error() {} },
    Deno: { env: { get: key => settings[key] }, serve: fn => { handler = fn; } },
    fetch: async url => {
      if (url.endsWith('/auth/v1/user')) return Response.json({ id: 'user' });
      if (url.includes('/rest/v1/profiles')) return Response.json([{ id: 'user', organisation_id: 'org', role: 'admin', active: true }]);
      if (networkError) throw new Error('network down');
      return new Response(null, { status: apnsStatus });
    },
    require(name) {
      if (name === 'npm:web-push@3') return {};
      if (name === 'https://esm.sh/@supabase/supabase-js@2') return { createClient: () => db };
      if (name === 'npm:jose@5') return { importPKCS8: async () => ({}), SignJWT: class { setProtectedHeader() { return this; } setIssuer() { return this; } setIssuedAt() { return this; } async sign() { return 'jwt'; } } };
      throw new Error(name);
    },
  };
  runInNewContext(compiled, sandbox);
  return handler;
}
const request = () => new Request('https://example.test/send-push', { method: 'POST', headers: { authorization: 'Bearer user', 'content-type': 'application/json' }, body: JSON.stringify({ event: 'test' }) });

test('reports missing Apple credentials instead of success', async () => {
  const response = await createHandler({ apnsConfig: false })(request());
  assert.equal(response.status, 503);
  assert.equal((await response.json()).native_failed, 1);
});

test('reports failed Apple requests rather than crashing or succeeding', async () => {
  for (const options of [{ apnsStatus: 403 }, { networkError: true }]) {
    const response = await createHandler(options)(request());
    assert.equal(response.status, 502);
    assert.equal((await response.json()).native_failed, 1);
  }
});

test('reports successful Apple acceptance', async () => {
  const response = await createHandler()(request());
  assert.equal(response.status, 200);
  assert.equal((await response.json()).native_sent, 1);
});

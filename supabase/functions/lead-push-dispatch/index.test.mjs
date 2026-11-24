import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';

const src = readFileSync(new URL('./index.ts', import.meta.url), 'utf8');
const compiled = ts.transpileModule(src, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
const id = 'acbf175c-a819-4e0f-9c70-65524fa5377a';
function setup({ alreadyClaimed = false, failApple = false, noDevices = false, receipts = 0 } = {}) {
  let handler;
  const calls = [];
  const db = { async rpc(name, args) {
    calls.push({ name, args });
    if (name === 'claim_lead_push') return { data: alreadyClaimed ? [] : [{ lead_id: 'lead-1', lead_name: 'Customer', job_type: 'Roof', attempt: 1 }] };
    if (name === 'lead_push_devices') return { data: noDevices ? [] : [{ device_id: 'device', device_token: 'token', environment: 'development', bundle_id: 'crm' }] };
    if (name === 'lead_push_delivery_count') return { data: receipts };
    return { error: null };
  } };
  const config = { SUPABASE_URL: 'https://example.test', SUPABASE_SERVICE_ROLE_KEY: 'secret', APNS_KEY_ID: 'key', APNS_TEAM_ID: 'team', APNS_PRIVATE_KEY: 'private' };
  const context = { exports: {}, Response, Request, console: { error() {} }, Deno: { env: { get: key => config[key] }, serve: fn => { handler = fn; } },
    fetch: async () => new Response(null, { status: failApple ? 503 : 200 }),
    require(name) {
      if (name.includes('supabase-js')) return { createClient: () => db };
      if (name === 'npm:jose@5') return { importPKCS8: async () => ({}), SignJWT: class { setProtectedHeader() { return this; } setIssuer() { return this; } setIssuedAt() { return this; } async sign() { return 'jwt'; } } };
      throw new Error(name);
    },
  };
  runInNewContext(compiled, context);
  return { handler, calls };
}
const req = event_id => new Request('https://example.test', { method: 'POST', body: JSON.stringify({ event_id }) });
test('rejects invalid capabilities without database access', async () => {
  const { handler, calls } = setup();
  assert.equal((await handler(req('invalid'))).status, 400);
  assert.equal(calls.length, 0);
});
test('a previously claimed event does not send again', async () => {
  const { handler, calls } = setup({ alreadyClaimed: true });
  assert.equal((await handler(req(id))).status, 200);
  assert.equal(calls.length, 1);
});
test('records successful device delivery before completing the event', async () => {
  const { handler, calls } = setup();
  assert.equal((await handler(req(id))).status, 200);
  assert.deepEqual(calls.map(c => c.name), ['claim_lead_push','lead_push_devices','mark_lead_push_delivered','finish_lead_push']);
  assert.equal(calls[2].args.p_attempt, 1);
  assert.equal(calls.at(-1).args.p_attempt, 1);
  assert.equal(calls.at(-1).args.p_success, true);
});
test('failed Apple request is recorded for retry', async () => {
  const { handler, calls } = setup({ failApple: true });
  assert.equal((await handler(req(id))).status, 502);
  assert.equal(calls.at(-1).args.p_success, false);
});
test('no device is retryable but previously completed deliveries finish', async () => {
  for (const [receipts, status] of [[0, 502], [1, 200]]) {
    const { handler } = setup({ noDevices: true, receipts });
    assert.equal((await handler(req(id))).status, status);
  }
});

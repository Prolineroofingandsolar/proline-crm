import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';

const source = readFileSync(new URL('./index.ts', import.meta.url), 'utf8').replace(/^import "jsr:[^"\n]+";\s*/, '');
const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None } }).outputText;
const adminId = '11111111-1111-1111-1111-111111111111';
const workerId = '22222222-2222-2222-2222-222222222222';
const organisation = '33333333-3333-3333-3333-333333333333';
function harness(profile, affected = [{ id: workerId }]) {
  let handler;
  const calls = [];
  vm.runInNewContext(code, {
    Deno: { env: { get: key => ({ SUPABASE_URL: 'https://test.invalid', SUPABASE_ANON_KEY: 'test-anon', SUPABASE_SERVICE_ROLE_KEY: 'test-service' })[key] }, serve: fn => { handler = fn; } },
    TextEncoder, Response, Request, crypto, Uint8Array, Date,
    fetch: async (url, options = {}) => {
      calls.push({ url, ...options });
      if (url.endsWith('/auth/v1/user')) return Response.json({ id: profile?.id ?? workerId });
      if (options.method === 'PATCH') return Response.json(affected);
      return Response.json(profile ? [profile] : []);
    },
  });
  return { calls, run: payload => handler(new Request('https://test.invalid/worker-invite', { method: 'POST', headers: { authorization: 'Bearer test-user-token', 'content-type': 'application/json' }, body: JSON.stringify(payload) })) };
}
test('worker cannot remove another employee access', async () => {
  const h = harness({ id: workerId, active: true, role: 'worker', organisation_id: organisation });
  assert.equal((await h.run({ action: 'deactivate', user_id: adminId })).status, 403);
  assert.ok(!h.calls.some(c => c.method === 'PATCH'));
});
test('inactive administrator cannot remove employee access', async () => {
  const h = harness({ id: adminId, active: false, role: 'admin', organisation_id: organisation });
  assert.equal((await h.run({ action: 'deactivate', user_id: workerId })).status, 403);
});
test('administrator cannot deactivate their own account', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
  assert.equal((await h.run({ action: 'deactivate', user_id: adminId })).status, 400);
});
test('employee deactivation is scoped to administrator organisation and keeps history', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
  const response = await h.run({ action: 'deactivate', user_id: workerId });
  assert.equal(response.status, 200);
  const mutation = h.calls.find(c => c.method === 'PATCH');
  assert.ok(mutation.url.includes(`organisation_id=eq.${organisation}`));
  assert.deepEqual(JSON.parse(mutation.body), { active: false });
  assert.ok(!h.calls.some(c => c.method === 'DELETE'));
});
test('unknown or other-organisation employee is not reported as removed', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation }, []);
  assert.equal((await h.run({ action: 'deactivate', user_id: workerId })).status, 404);
});
test('worker cannot create administrator invitations', async () => {
  const h = harness({ id: workerId, active: true, role: 'worker', organisation_id: organisation });
  assert.equal((await h.run({ action: 'create', email: 'test@example.invalid', role: 'admin' })).status, 403);
});
test('staff directory is administrator-only', async () => {
  const h = harness({ id: workerId, active: true, role: 'worker', organisation_id: organisation });
  assert.equal((await h.run({ action: 'list_staff' })).status, 403);
});
test('staff directory scopes both queries and excludes bank details and invitation secrets', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
  assert.equal((await h.run({ action: 'list_staff' })).status, 200);
  const queries = h.calls.filter(c => c.url.includes(`organisation_id=eq.${organisation}`));
  assert.equal(queries.length, 2);
  for (const query of queries) assert.ok(!/token_hash|bank_account|bank_sort|utr_number/.test(query.url));
});
test('staff cannot change another employee role or restore access', async () => {
  for (const action of ['update_staff', 'restore', 'cancel_invite']) {
    const h = harness({ id: workerId, active: true, role: 'worker', organisation_id: organisation });
    assert.equal((await h.run({ action, user_id: adminId, invitation_id: adminId, role: 'admin', day_rate: 200, cis_rate: 20 })).status, 403);
  }
});
test('administrator cannot change their own role', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
  assert.equal((await h.run({ action: 'update_staff', user_id: adminId, role: 'worker', day_rate: 100, cis_rate: 20 })).status, 400);
});
test('role and pay updates validate values before mutation', async () => {
  for (const updates of [{ role: 'owner', day_rate: 100, cis_rate: 20 }, { role: 'worker', day_rate: -1, cis_rate: 20 }, { role: 'worker', day_rate: 100, cis_rate: 0 }]) {
    const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
    assert.equal((await h.run({ action: 'update_staff', user_id: workerId, ...updates })).status, 400);
    assert.ok(!h.calls.some(c => c.method === 'PATCH'));
  }
});
test('staff update writes only validated role and pay fields in the same organisation', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
  assert.equal((await h.run({ action: 'update_staff', user_id: workerId, role: 'labourer', day_rate: 180.5, cis_rate: 30, active: true, organisation_id: 'other' })).status, 200);
  const mutation = h.calls.find(c => c.method === 'PATCH');
  assert.ok(mutation.url.includes(`organisation_id=eq.${organisation}`));
  assert.deepEqual(JSON.parse(mutation.body), { role: 'labourer', day_rate: 180.5, cis_rate: 30 });
});
test('restoring a staff member retains profile and history', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
  assert.equal((await h.run({ action: 'restore', user_id: workerId })).status, 200);
  assert.deepEqual(JSON.parse(h.calls.find(c => c.method === 'PATCH').body), { active: true });
});
test('invitation cancellation cannot remove accepted invitations or invitations in another organisation', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
  await h.run({ action: 'cancel_invite', invitation_id: workerId });
  const deletion = h.calls.find(c => c.method === 'DELETE');
  assert.ok(deletion.url.includes(`organisation_id=eq.${organisation}`));
  assert.ok(deletion.url.includes('accepted_at=is.null'));
});

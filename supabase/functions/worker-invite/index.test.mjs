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
function harness(profile, affected = [{ id: workerId }], syncReady = true, member = null) {
  let handler;
  const calls = [];
  vm.runInNewContext(code, {
    Deno: { env: { get: key => ({ SUPABASE_URL: 'https://test.invalid', SUPABASE_ANON_KEY: 'test-anon', SUPABASE_SERVICE_ROLE_KEY: 'test-service' })[key] }, serve: fn => { handler = fn; } },
    TextEncoder, Response, Request, crypto, Uint8Array, Date,
    fetch: async (url, options = {}) => {
      calls.push({ url, ...options });
      if (url.endsWith('/auth/v1/user')) return Response.json({ id: profile?.id ?? workerId });
      if (url.includes('/profiles?id=eq.') && url.includes('select=id,name,email')) return Response.json(affected.map(row => ({ name: 'Test Worker', email: 'old@example.invalid', ...row })));
      if (url.includes('/profiles?organisation_id=eq.') && url.includes('&email=eq.')) return Response.json(member ? [member] : []);
      if (url.endsWith('/rpc/staff_email_sync_ready')) return Response.json(syncReady);
      if (url.endsWith('/rpc/update_staff_details_safe')) return Response.json(null);
      if (url.endsWith('/rpc/update_staff_pay_safe')) return Response.json(true);
      if (url.includes('/auth/v1/admin/users/') && options.method === 'PUT') return Response.json({ id: workerId });
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
test('browser preflight permits Supabase client headers', async () => {
  let handler;
  vm.runInNewContext(code, { Deno: { env: { get: () => '' }, serve: fn => { handler = fn; } }, TextEncoder, Response, Request, crypto, Uint8Array, Date });
  const response = await handler(new Request('https://test.invalid/worker-invite', { method: 'OPTIONS', headers: { origin: 'https://proline-crm.pages.dev', 'access-control-request-method': 'POST', 'access-control-request-headers': 'authorization,apikey,content-type,x-client-info' } }));
  assert.equal(response.status, 200);
  assert.ok(response.headers.get('access-control-allow-headers').includes('x-client-info'));
  assert.ok(response.headers.get('access-control-allow-methods').includes('POST'));
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
test('employee cannot change another employee identity', async () => {
  for (const action of ['update_staff_email', 'update_staff_details']) {
    const h = harness({ id: workerId, active: true, role: 'worker', organisation_id: organisation });
    assert.equal((await h.run({ action, user_id: adminId, email: 'new@example.invalid', name: 'Other', role: 'admin', day_rate: 100, cis_rate: 20 })).status, 403);
    assert.ok(!h.calls.some(c => c.method === 'PUT' || c.url.includes('/rpc/')));
  }
});
test('email update checks company membership and trigger readiness before auth change', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
  assert.equal((await h.run({ action: 'update_staff_email', user_id: workerId, email: 'NEW@example.invalid' })).status, 200);
  const lookup = h.calls.find(c => c.url.includes('select=id,name,email'));
  assert.ok(lookup.url.includes(`organisation_id=eq.${organisation}`));
  assert.ok(h.calls.findIndex(c => c.url.endsWith('/rpc/staff_email_sync_ready')) < h.calls.findIndex(c => c.method === 'PUT'));
  assert.deepEqual(JSON.parse(h.calls.find(c => c.method === 'PUT').body), { email: 'new@example.invalid', email_confirm: true });
});
test('identity update for a different organisation never changes auth', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation }, []);
  assert.equal((await h.run({ action: 'update_staff_email', user_id: workerId, email: 'new@example.invalid' })).status, 404);
  assert.ok(!h.calls.some(c => c.method === 'PUT'));
});
test('email update fails closed when the email synchronisation trigger is unavailable', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation }, [{ id: workerId }], false);
  assert.equal((await h.run({ action: 'update_staff_email', user_id: workerId, email: 'new@example.invalid' })).status, 503);
  assert.ok(!h.calls.some(c => c.method === 'PUT'));
});
test('staff rename uses scoped transactional RPC with validated fields', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
  assert.equal((await h.run({ action: 'update_staff_details', user_id: workerId, name: ' New Name ', role: 'worker', day_rate: 150, cis_rate: 20 })).status, 200);
  assert.deepEqual(JSON.parse(h.calls.find(c => c.url.endsWith('/rpc/update_staff_details_safe')).body), { p_org: organisation, p_id: workerId, p_name: 'New Name', p_role: 'worker', p_rate: 150, p_cis: 20 });
});
test('employees cannot load or change another person’s bank details', async () => {
  for (const action of ['get_pay_details', 'update_pay_details']) {
    const h = harness({ id: workerId, active: true, role: 'worker', organisation_id: organisation });
    assert.equal((await h.run({ action, user_id: adminId })).status, 403);
  }
});
test('bank updates reject invalid data before any mutation', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
  const result = await h.run({ action: 'update_pay_details', user_id: workerId, bank_account_number: '123', expected: {} });
  assert.equal(result.status, 400);
  assert.ok(!h.calls.some(c => c.url.endsWith('/rpc/update_staff_pay_safe')));
});
test('bank details are sent in the request body and compared before updating', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
  const expected = { utr_number: null, bank_name: null, bank_account_number: null, bank_sort_code: null };
  const result = await h.run({ action: 'update_pay_details', user_id: workerId, utr_number: '1234567890', bank_name: 'Example', bank_account_number: '12345678', bank_sort_code: '12-34-56', expected });
  assert.equal(result.status, 200);
  const rpc = h.calls.find(c => c.url.endsWith('/rpc/update_staff_pay_safe'));
  assert.equal(JSON.parse(rpc.body).p_org, organisation);
  assert.deepEqual(JSON.parse(rpc.body).p_expected, expected);
  assert.ok(!h.calls.some(c => c.url.includes('12345678')));
});

test('admin can save an optional staff contact email without changing login', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
  assert.equal((await h.run({ action: 'update_staff_contact_email', user_id: workerId, email: ' Worker@Example.invalid ' })).status, 200);
  const write = h.calls.find(c => c.method === 'PATCH');
  assert.ok(write.url.includes(`organisation_id=eq.${organisation}`));
  assert.deepEqual(JSON.parse(write.body), { contact_email: 'worker@example.invalid' });
  assert.ok(!h.calls.some(c => c.url.includes('/auth/v1/admin/users/')));
});
test('only administrators can change staff contact email', async () => {
  const h = harness({ id: workerId, active: true, role: 'worker', organisation_id: organisation });
  assert.equal((await h.run({ action: 'update_staff_contact_email', user_id: adminId, email: 'new@example.invalid' })).status, 403);
  assert.ok(!h.calls.some(c => c.method === 'PATCH'));
});
test('invalid staff contact email is rejected', async () => {
  const h = harness({ id: adminId, active: true, role: 'admin', organisation_id: organisation });
  assert.equal((await h.run({ action: 'update_staff_contact_email', user_id: workerId, email: 'not-an-email' })).status, 400);
  assert.ok(!h.calls.some(c => c.method === 'PATCH'));
});

const admin = { id: adminId, active: true, role: 'admin', organisation_id: organisation };

test('inviting someone whose access was removed points to Restore instead of minting a dead code', async () => {
  const h = harness(admin, [{ id: workerId }], true, { id: workerId, name: 'Removed Person', active: false });
  const response = await h.run({ action: 'create', email: 'removed@example.invalid', role: 'worker' });
  assert.equal(response.status, 409);
  const body = await response.json();
  assert.match(body.error, /Removed Person/);
  assert.match(body.error, /Restore/);
  assert.ok(!h.calls.some(c => c.url.includes('/worker_invitations') && c.method === 'POST'));
});

test('inviting someone already on the team is refused', async () => {
  const h = harness(admin, [{ id: workerId }], true, { id: workerId, name: 'Active Person', active: true });
  const response = await h.run({ action: 'create', email: 'active@example.invalid', role: 'worker' });
  assert.equal(response.status, 409);
  assert.match((await response.json()).error, /already on your team/);
});

test('inviting a genuinely new address still works', async () => {
  const h = harness(admin, [{ id: workerId }], true, null);
  const response = await h.run({ action: 'create', email: 'new@example.invalid', role: 'worker' });
  assert.equal(response.status, 200);
  assert.ok(h.calls.some(c => c.url.includes('/worker_invitations') && c.method === 'POST'));
});

test('giving a login to someone whose access was removed points to Restore', async () => {
  const h = harness(admin, [{ id: workerId }], true, { id: workerId, name: 'Removed Person', active: false });
  const response = await h.run({ action: 'create_user', name: 'Removed Person', email: 'removed@example.invalid', password: 'TempPass12345', role: 'worker', cis_rate: 20 });
  assert.equal(response.status, 409);
  assert.match((await response.json()).error, /Restore/);
  assert.ok(!h.calls.some(c => c.url.endsWith('/auth/v1/admin/users') && c.method === 'POST'));
});

const pwAdmin = { id: adminId, active: true, role: 'admin', organisation_id: organisation };
const pwHarness = (profile, email = 'worker@example.invalid') => harness(profile, [{ id: workerId, email }]);

test('an administrator can set a new password for an employee', async () => {
  const h = pwHarness(pwAdmin);
  assert.equal((await h.run({ action: 'set_staff_password', user_id: workerId, password: 'BrandNewPass1' })).status, 200);
  const write = h.calls.find(c => c.url.includes('/auth/v1/admin/users/') && c.method === 'PUT');
  assert.ok(write, 'expected the auth password update');
  assert.deepEqual(JSON.parse(write.body), { password: 'BrandNewPass1' });
  assert.ok(h.calls.some(c => c.url.includes(`organisation_id=eq.${organisation}`)), 'lookup must be scoped to the company');
});

test('staff cannot set anyone password', async () => {
  const h = pwHarness({ id: workerId, active: true, role: 'worker', organisation_id: organisation });
  assert.equal((await h.run({ action: 'set_staff_password', user_id: adminId, password: 'BrandNewPass1' })).status, 403);
  assert.ok(!h.calls.some(c => c.method === 'PUT'));
});

test('a short password is rejected before anything is written', async () => {
  const h = pwHarness(pwAdmin);
  assert.equal((await h.run({ action: 'set_staff_password', user_id: workerId, password: 'short' })).status, 400);
  assert.ok(!h.calls.some(c => c.method === 'PUT'));
});

test('payroll-only staff have no login to reset', async () => {
  const h = pwHarness(pwAdmin, null);
  const response = await h.run({ action: 'set_staff_password', user_id: workerId, password: 'BrandNewPass1' });
  assert.equal(response.status, 400);
  assert.match((await response.json()).error, /Payroll-only/);
  assert.ok(!h.calls.some(c => c.method === 'PUT'));
});

test('an administrator is sent to Settings for their own password', async () => {
  const h = pwHarness(pwAdmin);
  assert.equal((await h.run({ action: 'set_staff_password', user_id: adminId, password: 'BrandNewPass1' })).status, 400);
  assert.ok(!h.calls.some(c => c.method === 'PUT'));
});

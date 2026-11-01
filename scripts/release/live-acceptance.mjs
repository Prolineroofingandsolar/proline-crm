// Creates only disposable accounts/records in an isolated organisation and cleans them up.
// Existing keys stay in memory; no credentials or customer records are logged.
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const ref = 'qzvdzzvkocmulcfujyea';
const url = `https://${ref}.supabase.co`;
const credentials = JSON.parse(execFileSync('supabase', ['projects', 'api-keys', '--project-ref', ref, '--output-format', 'json'], { env: { ...process.env, DO_NOT_TRACK: '1' }, encoding: 'utf8', timeout: 30000 }));
const key = name => credentials.keys.find(item => item.name === name)?.api_key;
assert.ok(key('service_role') && key('anon'), 'Existing project credentials unavailable');
const options = { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: (input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(20000) }) } };
const service = createClient(url, key('service_role'), options);
const anon = createClient(url, key('anon'), options);
const org = randomUUID();
const suffix = randomUUID().slice(0, 8);
const accounts = [];
const checks = [];
let organisationCreated = false;
const must = result => { if (result.error) throw new Error(result.error.message); return result.data; };
const pass = label => { checks.push(label); console.log(`PASS ${label}`); };
async function account(label, role) {
  const email = `release-${label}-${suffix}@prolinecrm.invalid`;
  const password = randomUUID() + randomUUID();
  const created = must(await service.auth.admin.createUser({ email, password, email_confirm: true }));
  accounts.push(created.user.id);
  must(await service.from('profiles').insert({ id: created.user.id, organisation_id: org, email, username: email, name: `Release ${label} ${suffix}`, role, active: true, day_rate: 100, cis_rate: 20 }));
  const client = createClient(url, key('anon'), options);
  must(await client.auth.signInWithPassword({ email, password }));
  return { id: created.user.id, name: `Release ${label} ${suffix}`, client };
}
async function staff(client, body) { return client.functions.invoke('worker-invite', { body }); }
try {
  must(await service.from('organisations').insert({ id: org, name: `Disposable release acceptance ${suffix}` }));
  organisationCreated = true;
  const admin = await account('admin', 'admin');
  const worker = await account('worker', 'worker');
  pass('isolated admin and employee sign in');
  async function mcp(client) {
    const session = must(await client.auth.getSession()).session;
    return fetch(`${url}/functions/v1/proline-mcp/mcp`, {
      method: 'POST', signal: AbortSignal.timeout(20000),
      headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ping' }),
    });
  }
  const mcpHealth = await fetch(`${url}/functions/v1/proline-mcp/health`, { signal: AbortSignal.timeout(20000) });
  assert.equal(mcpHealth.status, 200);
  assert.equal((await mcpHealth.json()).connector_version, '0.5.0');
  assert.equal((await mcp(admin.client)).status, 200);
  assert.equal((await mcp(worker.client)).status, 403);
  pass('deployed Grok connector accepts active admins and rejects employee access');
  must(await admin.client.from('organisations').update({ phone: '07000000000', address: 'Disposable test address' }).eq('id', org).select('id').single());
  const company = must(await worker.client.from('organisations').select('id,phone').single());
  assert.equal(company.id, org); assert.equal(company.phone, '07000000000');
  const unauthorisedCompany = await worker.client.from('organisations').update({ phone: '07000000001' }).eq('id', org).select('id');
  assert.ok(unauthorisedCompany.error || unauthorisedCompany.data.length === 0);
  pass('company details persist across accounts and employees cannot change them');
  const own = `release-own-${suffix}`, other = `release-other-${suffix}`;
  const initialVersion = '2026-11-01T12:00:00.000Z';
  must(await service.from('leads').insert([
    { id: own, organisation_id: org, name: 'Disposable assigned test job', assigned_to: worker.name, updated_at: initialVersion },
    { id: other, organisation_id: org, name: 'Disposable other test job', assigned_to: admin.name, updated_at: initialVersion },
  ]));
  const staffJobs = must(await worker.client.from('leads').select('id'));
  assert.deepEqual(staffJobs.map(row => row.id), [own]);
  const adminJobs = must(await admin.client.from('leads').select('id'));
  assert.deepEqual(new Set(adminJobs.map(row => row.id)), new Set([own, other]));
  pass('employee sees only assigned job; admin sees own organisation only');
  const profiles = must(await worker.client.from('profiles').select('id'));
  assert.deepEqual(profiles.map(row => row.id), [worker.id]);
  pass('employee cannot read coworker payroll profiles');
  const publicRead = await anon.from('leads').select('id').limit(1);
  assert.ok(publicRead.error, 'Anonymous customer read unexpectedly allowed');
  pass('anonymous customer reads denied');
  const ownUpdate = must(await worker.client.from('leads').update({ phone: '07000000000' }).eq('id', own).select('id'));
  assert.equal(ownUpdate.length, 1);
  const finance = await worker.client.from('leads').update({ value: 999 }).eq('id', own).select('id');
  assert.ok(finance.error, 'Employee changed a job value');
  const ownPay = await worker.client.from('profiles').update({ day_rate: 999 }).eq('id', worker.id).select('id');
  assert.ok(ownPay.error, 'Employee changed own payroll rate');
  pass('assigned job saves work; employee financial and pay-rate edits rejected');
  const current = must(await admin.client.from('leads').select('updated_at').eq('id', own).single());
  const first = must(await admin.client.from('leads').update({ stage: 'Quote Sent', updated_at: '2026-11-01T12:01:00.000Z' }).eq('id', own).eq('updated_at', current.updated_at).select('id'));
  assert.equal(first.length, 1);
  const stale = must(await admin.client.from('leads').update({ stage: 'Paid' }).eq('id', own).eq('updated_at', current.updated_at).select('id'));
  assert.equal(stale.length, 0);
  pass('Quote Sent saves and stale concurrent stage changes are rejected');
  const directory = must(await staff(admin.client, { action: 'list_staff' }));
  assert.deepEqual(new Set(directory.staff.map(row => row.id)), new Set([admin.id, worker.id]));
  const deniedDirectory = await staff(worker.client, { action: 'list_staff' });
  assert.ok(deniedDirectory.error);
  pass('live staff directory is administrator-only and company scoped');
  must(await staff(admin.client, { action: 'update_staff', user_id: worker.id, role: 'worker', day_rate: 180, cis_rate: 30 }));
  const updatedPay = must(await worker.client.from('profiles').select('day_rate,cis_rate').eq('id', worker.id).single());
  assert.equal(Number(updatedPay.day_rate), 180);
  assert.equal(updatedPay.cis_rate, 30);
  pass('administrator role and pay management updates the actual profile');
  must(await staff(admin.client, { action: 'deactivate', user_id: worker.id }));
  assert.equal(must(await worker.client.from('leads').select('id')).length, 0);
  assert.equal(must(await service.from('leads').select('id').eq('id', own)).length, 1);
  must(await staff(admin.client, { action: 'restore', user_id: worker.id }));
  assert.equal(must(await worker.client.from('leads').select('id')).length, 1);
  pass('deactivation blocks existing sessions; restoration works; job history retained');
  const email = `release-invite-${suffix}@prolinecrm.invalid`;
  const invitation = must(await staff(admin.client, { action: 'create', email, role: 'worker' }));
  const password = randomUUID() + randomUUID();
  const accepted = must(await staff(anon, { action: 'accept', token: invitation.code, name: `Release invited ${suffix}`, password, day_rate: 9999 }));
  assert.equal(accepted.email, email);
  const joined = createClient(url, key('anon'), options);
  const joinedSession = must(await joined.auth.signInWithPassword({ email, password }));
  accounts.push(joinedSession.user.id);
  const joinedProfile = must(await joined.from('profiles').select('organisation_id,role,day_rate').eq('id', joinedSession.user.id).single());
  assert.equal(joinedProfile.organisation_id, org);
  assert.equal(joinedProfile.role, 'worker');
  assert.equal(joinedProfile.day_rate, null);
  const reused = await staff(anon, { action: 'accept', token: invitation.code, name: 'Reuse test', password });
  assert.ok(reused.error);
  pass('invitation acceptance, employee login and single-use protection work');
  const cancelled = must(await staff(admin.client, { action: 'create', email: `release-cancel-${suffix}@prolinecrm.invalid`, role: 'worker' }));
  must(await staff(admin.client, { action: 'cancel_invite', invitation_id: cancelled.id }));
  assert.equal(must(await service.from('worker_invitations').select('id').eq('id', cancelled.id)).length, 0);
  pass('pending staff invitations can be cancelled');
  const payroll = must(await staff(admin.client, { action: 'create_user', name: `Release payroll ${suffix}`, email: '', password: '', role: 'labourer', day_rate: 120, cis_rate: 20 }));
  accounts.push(payroll.user_id);
  assert.equal(payroll.login_enabled, false);
  const payrollProfile = must(await service.from('profiles').select('email,day_rate').eq('id', payroll.user_id).single());
  assert.equal(payrollProfile.email, null);
  assert.equal(Number(payrollProfile.day_rate), 120);
  pass('payroll-only staff creation works without an app login');
  const session = must(await admin.client.auth.getSession());
  const refreshed = must(await admin.client.auth.refreshSession({ refresh_token: session.session.refresh_token }));
  assert.ok(refreshed.session.access_token);
  must(await staff(admin.client, { action: 'list_staff' }));
  assert.equal((await mcp(admin.client)).status, 200);
  pass('account refresh keeps authenticated staff management working');
} finally {
  let cleanupError = false;
  if (organisationCreated) {
    try {
      const remaining = must(await service.from('profiles').select('id').eq('organisation_id', org));
      for (const row of remaining) if (!accounts.includes(row.id)) accounts.push(row.id);
      for (const table of ['worker_invitations', 'leads']) must(await service.from(table).delete().eq('organisation_id', org));
      for (const id of accounts) must(await service.auth.admin.deleteUser(id));
      must(await service.from('organisations').delete().eq('id', org));
      console.log('CLEANUP PASS: disposable accounts and records removed; existing customer records untouched.');
    } catch (error) { cleanupError = true; console.error('CLEANUP FAILED for isolated organisation '+org+': '+error.message); }
  }
  console.log(`${checks.length} live acceptance checks passed.`);
  if (cleanupError) process.exitCode = 1;
}

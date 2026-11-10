// Run in the owner's signed-in Terminal. Creates an isolated, fictional review account.
import { execFileSync } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const ref = 'qzvdzzvkocmulcfujyea';
const org = 'f7e76220-2311-4f55-a296-52bd20ad6067';
const path = '/tmp/proline-apple-review-credentials.json';
const output = execFileSync('supabase', ['projects', 'api-keys', '--project-ref', ref, '--reveal', '--output', 'json'], {
  env: { ...process.env, DO_NOT_TRACK: '1' }, encoding: 'utf8', timeout: 30000,
});
const parsed = JSON.parse(output);
const keys = Array.isArray(parsed) ? parsed : parsed.keys;
const serviceKey = keys?.find(k => k.name === 'service_role')?.api_key;
const publicKey = keys?.find(k => k.name === 'anon')?.api_key;
if (!serviceKey || !publicKey) throw new Error('Supabase did not return the required project keys. No account was created.');
const options = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(`https://${ref}.supabase.co`, serviceKey, options);
const client = createClient(`https://${ref}.supabase.co`, publicKey, options);
const email = `apple-review-${randomUUID().slice(0, 8)}@example.com`;
const password = randomBytes(24).toString('base64url');
const must = ({ data, error }) => { if (error) throw error; return data; };
let id;
try {
  const workspace = must(await service.from('organisations').select('id,name').eq('id', org).single());
  if (!workspace.name.includes('fictional data')) throw new Error('Review workspace does not match expected setup.');
  const created = must(await service.auth.admin.createUser({ email, password, email_confirm: true }));
  id = created.user.id;
  must(await service.from('profiles').insert({ id, organisation_id: org, email, username: email, name: 'Apple Review', role: 'admin', active: true }));
  must(await client.auth.signInWithPassword({ email, password }));
  const profile = must(await client.from('profiles').select('id,organisation_id,role').eq('id', id).single());
  if (profile.organisation_id !== org || profile.role !== 'admin') throw new Error('Review profile isolation check failed.');
  const leads = must(await client.from('leads').select('id,organisation_id'));
  if (leads.length < 3 || leads.some(lead => lead.organisation_id !== org || !lead.id.startsWith('apple-review-job-'))) throw new Error('Review job isolation check failed.');
  const receipts = must(await client.from('monzo_receipts').select('id'));
  if (receipts.length) throw new Error('Review account can see business receipts.');
  writeFileSync(path, JSON.stringify({ email, password, userId: id, organisationId: org }, null, 2), { mode: 0o600, flag: 'wx' });
  console.log(`Review account created and tested with ${leads.length} fictional jobs. Credentials saved privately to ${path}`);
} catch (error) {
  if (id) {
    const deleted = await service.auth.admin.deleteUser(id);
    if (deleted.error) console.error(`Account cleanup failed for ${id}: ${deleted.error.message}`);
  }
  console.error(`Setup failed: ${error.message}`);
  process.exitCode = 1;
}

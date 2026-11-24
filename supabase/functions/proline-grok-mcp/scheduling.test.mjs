import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import * as core from './core.mjs';

const source = readFileSync(new URL('./index.ts', import.meta.url), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
function setup(row) {
  let handler;
  const context = { exports: {}, console, Date, URL, Request, Response, crypto: globalThis.crypto,
    Deno: { env: { get: () => undefined }, serve: () => {} },
    require(name) {
      if (name.includes('functions-js')) return {};
      if (name.includes('supabase-js')) return { createClient() {} };
      if (name === './core.mjs') return core;
      if (name === './http.mjs') return { ConnectionFailure: Error, createMcpHandler: value => { handler = value; return () => {}; } };
      if (name === './broker-auth.mjs') return { verifyAssertion() {} };
      throw new Error(name);
    },
  };
  runInNewContext(compiled, context);
  const service = { from(table) {
    assert.equal(table, 'leads');
    const filters = []; let changes;
    return { select() { return this; }, eq(key,value) { filters.push([key,value]); return this; }, update(value) { changes=value; return this; },
      async maybeSingle() {
        if (!filters.every(([k,v]) => row[k] === v)) return { data: null, error: null };
        if (changes) Object.assign(row, changes);
        return { data: { ...row }, error: null };
      } };
  } };
  return { call: (args, org = 'org-1') => handler.callTool('proline_update_job_dates', args, { user: { id: 'admin-1' }, profile: { organisation_id: org }, service }), handler };
}
const current = '2026-11-20T10:00:00.000Z';
const args = { job_id: 'job-1', expected_updated_at: current, start_date: '2026-12-10' };
const fixture = () => ({ id: 'job-1', organisation_id: 'org-1', updated_at: current, start_date: '2026-12-01', end_date: '2026-12-20' });
test('administrator scheduling preserves an unrequested end date and advances the version', async () => {
  const row = fixture(), { call, handler } = setup(row);
  assert.ok(handler.tools.some(t => t.name === 'proline_update_job_dates'));
  const result = await call(args);
  assert.equal(result.updated, true);
  assert.equal(row.start_date, '2026-12-10');
  assert.equal(row.end_date, '2026-12-20');
  assert.ok(Date.parse(row.updated_at) > Date.parse(current));
  await assert.rejects(call(args), /changed/);
});
test('scheduling cannot update another organisation or produce conflicting dates', async () => {
  const row = fixture(), { call } = setup(row);
  await assert.rejects(call(args, 'other-org'), /not found/);
  await assert.rejects(call({ ...args, start_date: '2026-12-21' }), /before/);
  assert.equal(row.updated_at, current);
});

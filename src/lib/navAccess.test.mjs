import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ADMIN_ONLY_PAGES, staffVisible } from './navAccess.ts';

// The pages AGENTS.md says staff must never see. If someone removes one from
// ADMIN_ONLY_PAGES, this fails instead of quietly exposing it.
const ADMIN_ONLY = ['dashboard', 'pipeline', 'leads', 'contacts', 'files', 'reports', 'cis', 'banking', 'office', 'settings'];
// The pages staff are meant to use.
const STAFF = ['jobs', 'tasks', 'calendar', 'timesheet', 'tools'];

test('every admin-only page listed in AGENTS.md stays admin-only', () => {
  for (const page of ADMIN_ONLY) assert.ok(ADMIN_ONLY_PAGES.has(page), `${page} must stay admin-only`);
  assert.equal(ADMIN_ONLY_PAGES.size, ADMIN_ONLY.length);
});

test('the pages staff work from are never admin-only', () => {
  for (const page of STAFF) assert.ok(!ADMIN_ONLY_PAGES.has(page), `${page} must stay open to staff`);
});

test('a staff menu cannot offer an admin-only page', () => {
  const menu = [{ id: 'jobs' }, { id: 'pipeline' }, { id: 'tasks' }, { id: 'banking' }];
  assert.deepEqual(staffVisible(menu), [{ id: 'jobs' }, { id: 'tasks' }]);
});

test('an empty menu stays empty and a staff-only menu is untouched', () => {
  assert.deepEqual(staffVisible([]), []);
  const safe = [{ id: 'jobs' }, { id: 'timesheet' }];
  assert.deepEqual(staffVisible(safe), safe);
});

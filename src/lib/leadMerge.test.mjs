import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mergeLead, LeadConflict } from './leadMerge.ts';
const base = { id: 'test-job', stage: 'New Lead', phone: '1', tasks: [], value: 100, deposit: 0, deposit_paid: false, balance: 100 };
test('Quote Sent preserves another employee phone edit', () => {
  assert.deepEqual(mergeLead(base, { ...base, stage: 'Quote Sent' }, { ...base, phone: '2' }), { ...base, stage: 'Quote Sent', phone: '2', progress: 0 });
});
test('same-field competing edits require review', () => {
  assert.throws(() => mergeLead(base, { ...base, phone: '3' }, { ...base, phone: '2' }), LeadConflict);
});
test('independent task additions survive', () => {
  const result = mergeLead(base, { ...base, tasks: [{ id: 'a', completed: true }] }, { ...base, tasks: [{ id: 'b', completed: false }] });
  assert.equal(result.tasks.length, 2); assert.equal(result.progress, 50);
});
test('financial changes cannot merge into inconsistent balances', () => {
  assert.throws(() => mergeLead(base, { ...base, value: 200, balance: 200 }, { ...base, deposit: 20, deposit_paid: true, balance: 80 }), LeadConflict);
});
test('server timestamps do not create false conflicts', () => {
  assert.equal(mergeLead({ ...base, updated_at: 'old' }, { ...base, stage: 'Quote Sent' }, { ...base, updated_at: 'new' }).stage, 'Quote Sent');
});
test('queued edits on different tasks merge with the acknowledged first save', () => {
  const initial = { ...base, tasks: [{ id: 'a', completed: false }, { id: 'b', completed: false }] };
  const first = { ...initial, tasks: [{ id: 'a', completed: true }, { id: 'b', completed: false }] };
  const second = { ...first, tasks: [{ id: 'a', completed: true }, { id: 'b', completed: true }] };
  const acknowledged = mergeLead(initial, first, { ...initial, phone: '2' });
  const result = mergeLead(first, second, acknowledged);
  assert.equal(result.phone, '2'); assert.equal(result.progress, 100);
});
test('deleting a task cannot erase another employee edit to that task', () => {
  const initial = { ...base, tasks: [{ id: 'a', completed: false }] };
  assert.throws(() => mergeLead(initial, { ...base, tasks: [] }, { ...base, tasks: [{ id: 'a', completed: true }] }), LeadConflict);
});
test('an uncertain network response can be retried without duplicating additions', () => {
  const draft = { ...base, notes: [{ id: 'stable-note', content: 'Test only' }] };
  const initial = { ...base, notes: [] };
  const accepted = mergeLead(initial, draft, initial);
  assert.deepEqual(mergeLead(initial, draft, accepted).notes, draft.notes);
});
test('identical server edits are accepted', () => {
  const draft = { ...base, stage: 'Quote Sent' };
  assert.equal(mergeLead(base, draft, draft).stage, 'Quote Sent');
});

import test from "node:test";
import assert from "node:assert/strict";
import { saveBruceReply } from "./core.mjs";

function service(row) {
  let patch, filters = [];
  const query = {
    update(value) { patch = value; return this; },
    eq(key, value) { filters.push(r => r[key] === value); return this; },
    contains(key, value) { filters.push(r => Object.entries(value).every(([k, v]) => r[key]?.[k] === v)); return this; },
    in(key, values) { filters.push(r => values.includes(r[key])); return this; },
    select() { return this; },
    async maybeSingle() { if (!filters.every(f => f(row))) return { data: null }; Object.assign(row, patch); return { data: { id: row.id } }; },
  };
  return { from(name) { assert.equal(name, "ai_agent_commands"); return query; } };
}
const id = "66d49767-1280-4bc1-88d6-229dbd31be39";
const request = () => ({ id, organisation_id: "owner", status: "accepted", payload: { source: "bruce_assistant" } });

test("Bruce reply only completes a pending request in the caller organisation", async () => {
  const row = request();
  await assert.rejects(saveBruceReply(service(row), "other", { command_id: id, reply: "Hello" }));
  assert.equal(row.status, "accepted");
  assert.deepEqual(await saveBruceReply(service(row), "owner", { command_id: id, reply: " Hello " }), { delivered: true, command_id: id });
  assert.deepEqual(row.result, { message: "Hello" });
  await assert.rejects(saveBruceReply(service(row), "owner", { command_id: id, reply: "Again" }));
});

test("Bruce reply rejects malformed IDs and unrelated commands", async () => {
  const row = request(); row.payload.source = "proline_virtual_office";
  await assert.rejects(saveBruceReply(service(row), "owner", { command_id: id, reply: "Hello" }));
  await assert.rejects(saveBruceReply(service(row), "owner", { command_id: "-".repeat(36), reply: "Hello" }));
  await assert.rejects(saveBruceReply(service(row), "owner", { command_id: id, reply: "  " }));
});

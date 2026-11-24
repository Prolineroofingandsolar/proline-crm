import assert from "node:assert/strict";
import test from "node:test";
import { AGENT_WRITE_TOOLS, OWNER_ACTION_TOOLS, analyse, asToolResult, londonToday, ownerActionChanges, pipelineSummary, prepareFollowUp, TOOLS, toolsForConfig, validateArguments } from "./core.mjs";

test("advertises the read-only Grok Bot tools", () => {
  assert.deepEqual(TOOLS.map((tool) => tool.name), [
    "proline_status",
    "proline_daily_plan",
    "proline_pipeline_summary",
    "proline_find_jobs",
    "proline_prepare_follow_up",
  ]);
  for (const tool of TOOLS) {
    assert.equal(tool.annotations.readOnlyHint, true);
    assert.equal(tool.annotations.destructiveHint, false);
    assert.equal(tool.securitySchemes[0].type, "oauth2");
  }
});

test("prepares follow-ups without sending and refuses invalid or stale payment states", () => {
  const job = { id: "job-1", job_ref: "P-1", name: "Taylor", email: "taylor@example.com", stage: "Quote Sent", deposit: 500, deposit_paid: false, updated_at: "2026-11-15T10:00:00Z" };
  const quote = prepareFollowUp(job, "quote_follow_up");
  assert.equal(quote.sent, false);
  assert.equal(quote.recipient, "taylor@example.com");
  assert.equal(quote.based_on_updated_at, job.updated_at);
  assert.throws(() => prepareFollowUp(null, "quote_follow_up"), /not found/);
  assert.throws(() => prepareFollowUp({ ...job, email: "" }, "quote_follow_up"), /email/);
  assert.throws(() => prepareFollowUp(job, "deposit_reminder"), /outstanding deposit/);
  const deposit = prepareFollowUp({ ...job, stage: "Won" }, "deposit_reminder");
  assert.match(deposit.body, /£500\.00/);
  assert.throws(() => prepareFollowUp({ ...job, stage: "Won", deposit_paid: true }, "deposit_reminder"), /outstanding deposit/);
  assert.throws(() => validateArguments("proline_prepare_follow_up", { job_id: "job-1", kind: "send" }), /invalid/);
});

test("keeps business writes gated while allowing a check-in-only pilot", () => {
  const pilot = toolsForConfig(true, false);
  assert.deepEqual(pilot.map((tool) => tool.name), [
    ...TOOLS.map((tool) => tool.name),
    ...OWNER_ACTION_TOOLS.map((tool) => tool.name),
    "proline_update_job_dates",
    "proline_check_for_changes",
    "proline_agent_checkin",
  ]);
  assert.equal(pilot.at(-1).annotations.readOnlyHint, false);
  assert.deepEqual(toolsForConfig(false, false).map(tool => tool.name), [...TOOLS, ...OWNER_ACTION_TOOLS].map(tool => tool.name).concat("proline_update_job_dates"));
  assert.equal(toolsForConfig(true, true).length, TOOLS.length + OWNER_ACTION_TOOLS.length + AGENT_WRITE_TOOLS.length);
});

test("explicit owner actions protect versions, preserve checklist work, and calculate deposit balance", () => {
  const job = { id: "j1", stage: "Quote Sent", updated_at: "2026-11-15T10:00:00Z", value: 5000, deposit: 1500, deposit_paid: false, tasks: [
    { id: "old", title: "Old template", completed: false, isTemplate: true },
    { id: "done", title: "Finished", completed: true, isTemplate: true },
    { id: "custom", title: "Custom", completed: false },
  ] };
  const args = { job_id: "j1", expected_updated_at: job.updated_at, stage: "Won" };
  const changes = ownerActionChanges(job, "proline_move_job_stage", args, "2026-11-15", () => "new");
  assert.equal(changes.won_date, "2026-11-15");
  assert.deepEqual(changes.tasks.slice(0, 2).map(t => t.id), ["done", "custom"]);
  assert.ok(changes.tasks.some(t => t.title === "Order materials"));
  assert.equal(changes.progress, Math.round(100 / changes.tasks.length));
  assert.throws(() => ownerActionChanges(job, "proline_move_job_stage", { ...args, expected_updated_at: "2026-11-14T10:00:00Z" }, "2026-11-15"), /changed/);
  assert.throws(() => validateArguments("proline_move_job_stage", { ...args, stage: "Paid" }), /invalid/);
  assert.deepEqual(ownerActionChanges(job, "proline_record_deposit", { ...args, expected_deposit: 1500 }, "2026-11-15"), { deposit_paid: true, balance: 3500 });
  assert.throws(() => ownerActionChanges(job, "proline_record_deposit", { ...args, expected_deposit: 1000 }, "2026-11-15"), /changed/);
  assert.equal(ownerActionChanges({ ...job, deposit_paid: true }, "proline_record_deposit", { ...args, expected_deposit: 1500 }, "2026-11-15"), null);
  assert.throws(() => validateArguments("proline_record_deposit", { job_id: "j1", expected_updated_at: job.updated_at, expected_deposit: 0 }), /greater/);
});

test("job date changes require explicit valid dates and the current job version", () => {
  const name = "proline_update_job_dates";
  const base = { job_id: "job-1", expected_updated_at: "2026-11-04T11:00:00Z" };
  assert.throws(() => validateArguments(name, base), /start or end date/);
  assert.throws(() => validateArguments(name, { ...base, start_date: "2026-02-30" }), /valid/);
  assert.throws(() => validateArguments(name, { ...base, start_date: "2026-11-13", end_date: "2026-11-12" }), /before/);
  assert.throws(() => validateArguments(name, { job_id: "job-1", start_date: "2026-11-13" }), /expected_updated_at/);
  assert.doesNotThrow(() => validateArguments(name, { ...base, start_date: "2026-11-13" }));
  assert.equal(toolsForConfig(true, false).find(tool => tool.name === name).annotations.readOnlyHint, false);
  assert.equal(toolsForConfig(false, false).filter(tool => tool.name === name).length, 1);
  assert.equal(toolsForConfig(true, true).find(tool => tool.name === name).annotations.readOnlyHint, false);
});

test("caps Virtual Office check-ins at eight findings", () => {
  const base = {
    agent_slug: "stace",
    provider_run_id: "run-1",
    status: "succeeded",
    summary: "Three exceptions found.",
  };
  assert.doesNotThrow(() => validateArguments("proline_agent_checkin", { ...base, items: Array.from({ length: 8 }, () => ({})) }));
  assert.throws(() => validateArguments("proline_agent_checkin", { ...base, items: Array.from({ length: 9 }, () => ({})) }), /eight items/);
});

test("summarises pipeline value and balances without customer details", () => {
  const summary = pipelineSummary({
    fetched_at: "2026-09-15T09:00:00Z",
    leads: [
      { name: "Private Customer", stage: "Quote Sent", value: 1200, balance: 1200 },
      { name: "Another Customer", stage: "In Progress", value: 3000, balance: 1800 },
    ],
  });
  assert.equal(summary.jobs_checked, 2);
  assert.equal(summary.total_quoted_value, 4200);
  assert.equal(summary.total_outstanding_balance, 3000);
  assert.equal(JSON.stringify(summary).includes("Private Customer"), false);
});

test("validates job searches and planner dates", () => {
  assert.doesNotThrow(() => validateArguments("proline_find_jobs", { query: "Taylor" }));
  assert.doesNotThrow(() => validateArguments("proline_daily_plan", { today: "2026-09-07" }));
  assert.throws(() => validateArguments("proline_find_jobs", { query: "" }), /Query must contain/);
  assert.throws(() => validateArguments("proline_daily_plan", { today: "07-09-2026" }), /YYYY-MM-DD/);
  assert.throws(() => validateArguments("proline_status", { token: "no" }), /Unexpected argument/);
});

test("ranks overdue work before lower-priority findings", () => {
  const report = analyse({
    fetched_at: "2026-09-07T07:00:00Z",
    leads: [
      { id: "late", job_ref: "J-1", name: "Late Job", stage: "In Progress", end_date: "2026-09-01", assigned_to: "Sam", deposit: 0, tasks: [] },
      { id: "new", job_ref: "J-2", name: "New Lead", stage: "New Lead", tasks: [] },
    ],
    tasks: [],
  }, "2026-09-07");
  assert.equal(report.alerts[0].kind, "overdue_job");
  assert.equal(report.alerts.at(-1).kind, "new_enquiry");
});

test("returns MCP-compatible structured results", () => {
  const result = asToolResult({ connected: true });
  assert.equal(result.content[0].type, "text");
  assert.deepEqual(result.structuredContent, { connected: true });
});

test("uses a London calendar date", () => {
  assert.match(londonToday(new Date("2026-01-01T00:30:00Z")), /^2026-01-01$/);
});


test("accepts email enquiries without mislabelling their source and rejects unknown sources", () => {
  const lead = { agent_slug: "rodney", source: "email", source_event_id: "gmail-thread-123", customer_name: "Test enquiry", email: "customer@example.com", job_type: "Roof Repair", evidence: "Customer requested a roof repair by email." };
  const enabled = toolsForConfig(true, true);
  const definition = enabled.find(tool => tool.name === "proline_create_verified_lead");
  assert.deepEqual(definition.inputSchema.properties.source.enum, ["website", "mybuilder_shortlisted", "email"]);
  assert.doesNotThrow(() => validateArguments("proline_create_verified_lead", lead, enabled));
  assert.throws(() => validateArguments("proline_create_verified_lead", { ...lead, source: "spam" }, enabled));
  assert.equal(toolsForConfig(true, false).some(tool => tool.name === "proline_create_verified_lead"), false);
});

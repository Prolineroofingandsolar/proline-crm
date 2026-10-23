import assert from "node:assert/strict";
import test from "node:test";
import { AGENT_WRITE_TOOLS, analyse, asToolResult, londonToday, PILOT_TOOLS, pipelineSummary, TOOLS, toolsForConfig, validateArguments } from "./core.mjs";

test("advertises the four read-only Grok Bot tools", () => {
  assert.deepEqual(TOOLS.map((tool) => tool.name), [
    "proline_status",
    "proline_daily_plan",
    "proline_pipeline_summary",
    "proline_find_jobs",
  ]);
  for (const tool of TOOLS) {
    assert.equal(tool.annotations.readOnlyHint, true);
    assert.equal(tool.annotations.destructiveHint, false);
    assert.equal(tool.securitySchemes[0].type, "oauth2");
  }
});

test("keeps business writes gated while allowing a check-in-only pilot", () => {
  const pilot = toolsForConfig(true, false);
  assert.deepEqual(pilot.map((tool) => tool.name), [
    ...TOOLS.map((tool) => tool.name),
    "proline_check_for_changes",
    "proline_agent_checkin",
  ]);
  assert.equal(pilot.at(-1).annotations.readOnlyHint, false);
  assert.deepEqual(toolsForConfig(false, false), TOOLS);
  assert.equal(toolsForConfig(true, true).length, TOOLS.length + AGENT_WRITE_TOOLS.length);
});

test("exposes only controlled employee actions when writes are enabled", () => {
  assert.deepEqual(AGENT_WRITE_TOOLS.map((tool) => tool.name), [
    "proline_check_for_changes",
    "proline_agent_checkin",
    "proline_create_internal_task",
    "proline_update_internal_task",
    "proline_add_job_note",
    "proline_complete_job_task",
    "proline_complete_general_task",
    "proline_create_verified_lead",
    "proline_suggest_job_materials",
    "proline_submit_action_proposal",
  ]);
  for (const tool of AGENT_WRITE_TOOLS) {
    assert.equal(tool.annotations.destructiveHint, false);
  }
});

test("validates controlled note and completion actions", () => {
  assert.doesNotThrow(() => validateArguments("proline_add_job_note", {
    agent_slug: "stace", job_id: "job-1", note: "Checked scaffolding status; awaiting confirmation.", evidence: "Worker update in ProLine at 08:10.",
  }));
  assert.doesNotThrow(() => validateArguments("proline_complete_job_task", {
    agent_slug: "stace", job_id: "job-1", task_id: "task-1", completion_note: "Confirmed in CRM evidence.", evidence: "Worker marked delivery received with a photo.",
  }));
  assert.doesNotThrow(() => validateArguments("proline_complete_general_task", {
    agent_slug: "stace", task_id: "task-2", evidence: "The requested internal comparison run completed successfully.",
  }));
  assert.doesNotThrow(() => validateArguments("proline_suggest_job_materials", {
    agent_slug: "stace",
    job_id: "job-1",
    summary: "Starter list based on the recorded job type; quantities need site confirmation.",
    materials: [{ name: "Breathable membrane", quantity: 2, unit: "roll", reason: "Roof covering renewal", basis: "estimate" }],
  }));
  assert.throws(() => validateArguments("proline_add_job_note", {
    agent_slug: "stace", job_id: "job-1", note: "", evidence: "Worker update.",
  }));
  assert.throws(() => validateArguments("proline_complete_general_task", {
    agent_slug: "stace", task_id: "task-2",
  }), /Missing argument: evidence/);
  assert.doesNotThrow(() => validateArguments("proline_create_verified_lead", {
    agent_slug: "rodney", source: "mybuilder_shortlisted", source_event_id: "mb-123",
    customer_name: "Customer", job_type: "Roof Repair", evidence: "MyBuilder confirmed that contact details were shared.",
  }));
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
  assert.throws(() => validateArguments("proline_agent_checkin", {
    ...base, summary: Array.from({ length: 301 }, () => "word").join(" "), items: [],
  }), /300 words/);
});

test("pilot tools include a lightweight change check", () => {
  assert.deepEqual(PILOT_TOOLS.map((tool) => tool.name), ["proline_check_for_changes", "proline_agent_checkin"]);
  assert.equal(PILOT_TOOLS[0].annotations.readOnlyHint, true);
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

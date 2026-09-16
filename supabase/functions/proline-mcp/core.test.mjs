import assert from "node:assert/strict";
import test from "node:test";
import { analyse, asToolResult, londonToday, pipelineSummary, TOOLS, validateArguments } from "./core.mjs";

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

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PROJECT_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BRIDGE_TOKEN = Deno.env.get("PAPERCLIP_BRIDGE_TOKEN") ?? "";
const ORGANISATION_ID = Deno.env.get("PAPERCLIP_ORGANISATION_ID") ?? "";

const service = createClient(PROJECT_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

async function digest(value: string) {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function authorised(request: Request) {
  const supplied = request.headers.get("x-proline-bridge-token") ?? "";
  if (!BRIDGE_TOKEN || !ORGANISATION_ID || !supplied) return false;
  return (await digest(supplied)) === (await digest(BRIDGE_TOKEN));
}

function text(value: unknown, max = 240) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function nullableText(value: unknown, max = 240) {
  const clean = text(value, max);
  return clean || null;
}

function timestamp(value: unknown) {
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) return null;
  return new Date(value).toISOString();
}

function asArray(value: unknown, max: number) {
  return Array.isArray(value) ? value.slice(0, max) : [];
}

async function replaceRows(
  table: string,
  idColumn: string,
  rows: Record<string, unknown>[],
) {
  if (rows.length) {
    const { error } = await service.from(table).upsert(rows, {
      onConflict: `organisation_id,${idColumn}`,
    });
    if (error) throw new Error(`${table} could not be updated: ${error.message}`);
  }

  const { data: current, error: currentError } = await service
    .from(table)
    .select(idColumn)
    .eq("organisation_id", ORGANISATION_ID);
  if (currentError) throw new Error(`${table} could not be checked: ${currentError.message}`);

  const keep = new Set(rows.map((row) => String(row[idColumn])));
  const stale = (current ?? [])
    .map((row) => String((row as Record<string, unknown>)[idColumn]))
    .filter((id) => !keep.has(id));
  if (stale.length) {
    const { error } = await service
      .from(table)
      .delete()
      .eq("organisation_id", ORGANISATION_ID)
      .in(idColumn, stale);
    if (error) throw new Error(`${table} stale rows could not be removed: ${error.message}`);
  }
}

async function saveSnapshot(body: Record<string, unknown>) {
  if (text(body.organisationId, 64) !== ORGANISATION_ID) {
    return json({ error: "organisation_mismatch" }, 403);
  }

  const companyId = text(body.companyId, 100);
  if (!companyId) return json({ error: "company_id_required" }, 422);
  const now = new Date().toISOString();

  const agents = asArray(body.agents, 250).map((value) => {
    const row = value as Record<string, unknown>;
    return {
      organisation_id: ORGANISATION_ID,
      paperclip_agent_id: text(row.id, 100),
      name: text(row.name, 100) || "Unnamed agent",
      shortname: nullableText(row.shortname, 100),
      title: nullableText(row.title, 180),
      role: nullableText(row.role, 100),
      status: text(row.status, 50) || "idle",
      adapter_type: nullableText(row.adapterType, 80),
      heartbeat_enabled: row.heartbeatEnabled === true,
      heartbeat_interval_seconds: Number.isFinite(Number(row.heartbeatIntervalSeconds))
        ? Math.max(0, Math.round(Number(row.heartbeatIntervalSeconds)))
        : null,
      last_run_at: timestamp(row.lastRunAt),
      synced_at: now,
    };
  }).filter((row) => row.paperclip_agent_id);

  const issues = asArray(body.issues, 2000).map((value) => {
    const row = value as Record<string, unknown>;
    return {
      organisation_id: ORGANISATION_ID,
      paperclip_issue_id: text(row.id, 100),
      identifier: nullableText(row.identifier, 80),
      title: text(row.title, 300) || "Untitled task",
      status: text(row.status, 50) || "todo",
      priority: nullableText(row.priority, 30),
      assignee_agent_id: nullableText(row.assigneeAgentId, 100),
      project_id: nullableText(row.projectId, 100),
      created_at: timestamp(row.createdAt),
      updated_at: timestamp(row.updatedAt),
      synced_at: now,
    };
  }).filter((row) => row.paperclip_issue_id);

  const approvals = asArray(body.approvals, 500).map((value) => {
    const row = value as Record<string, unknown>;
    return {
      organisation_id: ORGANISATION_ID,
      paperclip_approval_id: text(row.id, 100),
      approval_type: nullableText(row.type, 100),
      status: text(row.status, 50) || "pending",
      requested_by_agent_id: nullableText(row.requestedByAgentId, 100),
      issue_id: nullableText(row.issueId, 100),
      created_at: timestamp(row.createdAt),
      resolved_at: timestamp(row.resolvedAt),
      synced_at: now,
    };
  }).filter((row) => row.paperclip_approval_id);

  const activity = asArray(body.activity, 300).map((value) => {
    const row = value as Record<string, unknown>;
    return {
      organisation_id: ORGANISATION_ID,
      paperclip_activity_id: text(row.id, 120),
      action: text(row.action, 180) || "Agent activity",
      actor_agent_id: nullableText(row.actorAgentId, 100),
      actor_name: nullableText(row.actorName, 100),
      issue_identifier: nullableText(row.issueIdentifier, 80),
      issue_title: nullableText(row.issueTitle, 300),
      created_at: timestamp(row.createdAt) ?? now,
      synced_at: now,
    };
  }).filter((row) => row.paperclip_activity_id);

  try {
    await Promise.all([
      replaceRows("paperclip_agents", "paperclip_agent_id", agents),
      replaceRows("paperclip_issues", "paperclip_issue_id", issues),
      replaceRows("paperclip_approvals", "paperclip_approval_id", approvals),
      replaceRows("paperclip_activity", "paperclip_activity_id", activity),
    ]);
    const { error } = await service.from("paperclip_connection_status").upsert({
      organisation_id: ORGANISATION_ID,
      paperclip_company_id: companyId,
      bridge_instance: nullableText(body.bridgeInstance, 120),
      connected: true,
      last_seen_at: now,
      last_success_at: now,
      last_error: null,
      synced_at: now,
    });
    if (error) throw error;
    return json({ ok: true, counts: { agents: agents.length, issues: issues.length, approvals: approvals.length, activity: activity.length } });
  } catch (error) {
    const message = error instanceof Error ? error.message.slice(0, 500) : "Snapshot failed";
    await service.from("paperclip_connection_status").upsert({
      organisation_id: ORGANISATION_ID,
      paperclip_company_id: companyId,
      bridge_instance: nullableText(body.bridgeInstance, 120),
      connected: false,
      last_seen_at: now,
      last_error: message,
      synced_at: now,
    });
    return json({ error: message }, 500);
  }
}

async function claimCommands(request: Request) {
  const url = new URL(request.url);
  if (url.searchParams.get("organisation_id") !== ORGANISATION_ID) {
    return json({ error: "organisation_mismatch" }, 403);
  }
  const { data, error } = await service.rpc("claim_paperclip_commands", {
    target_organisation: ORGANISATION_ID,
    command_limit: 20,
  });
  if (error) return json({ error: error.message }, 500);
  return json({ commands: data ?? [] });
}

async function acknowledge(body: Record<string, unknown>) {
  if (text(body.organisationId, 64) !== ORGANISATION_ID) {
    return json({ error: "organisation_mismatch" }, 403);
  }
  const commandId = text(body.commandId, 64);
  const status = body.status === "succeeded" ? "succeeded" : "failed";
  if (!commandId) return json({ error: "command_id_required" }, 422);
  const { data, error } = await service
    .from("paperclip_commands")
    .update({
      status,
      completed_at: new Date().toISOString(),
      result: status === "succeeded" && body.result && typeof body.result === "object" ? body.result : null,
      error: status === "failed" ? nullableText(body.error, 500) ?? "Command failed" : null,
    })
    .eq("id", commandId)
    .eq("organisation_id", ORGANISATION_ID)
    .eq("status", "processing")
    .select("id")
    .maybeSingle();
  if (error) return json({ error: error.message }, 500);
  if (!data) return json({ error: "command_not_found" }, 404);
  return json({ ok: true });
}

Deno.serve(async (request) => {
  if (!(await authorised(request))) return json({ error: "unauthorised" }, 401);
  const url = new URL(request.url);
  try {
    if (request.method === "POST" && url.pathname.endsWith("/snapshot")) {
      return saveSnapshot(await request.json());
    }
    if (request.method === "GET" && url.pathname.endsWith("/commands")) {
      return claimCommands(request);
    }
    if (request.method === "POST" && url.pathname.endsWith("/ack")) {
      return acknowledge(await request.json());
    }
    return json({ error: "not_found" }, 404);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message.slice(0, 500) : "Unexpected error" }, 500);
  }
});

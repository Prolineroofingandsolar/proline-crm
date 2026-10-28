import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PROJECT_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function cleanText(value: unknown, max: number) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

async function authenticate(request: Request) {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return null;
  const userClient = createClient(PROJECT_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error } = await userClient.auth.getUser();
  if (error || !user) return null;
  const service = createClient(PROJECT_URL, SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: profile } = await service
    .from("profiles")
    .select("id,organisation_id,role,active")
    .eq("id", user.id)
    .eq("active", true)
    .maybeSingle();
  if (!profile || profile.role !== "admin" || !profile.organisation_id) return null;
  return { user, profile, service };
}

type WebhookConfig = { url: string; secret: string };

function webhookConfig(slug: string): WebhookConfig | null {
  let configured: unknown;
  try {
    const parsed = JSON.parse(Deno.env.get("GROK_WEBHOOKS_JSON") ?? "{}");
    configured = parsed && typeof parsed === "object" ? (parsed as Record<string, unknown>)[slug] : null;
  } catch {
    configured = undefined;
  }
  const record = configured && typeof configured === "object" ? configured as Record<string, unknown> : {};
  const envPrefix = slug.toUpperCase().replaceAll("-", "_");
  const url = cleanText(record.url ?? Deno.env.get(`GROK_${envPrefix}_WEBHOOK_URL`), 2000);
  const secret = cleanText(record.secret ?? Deno.env.get(`GROK_${envPrefix}_WEBHOOK_SECRET`), 1000);
  if (!url || !secret) return null;
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:") return null;
  } catch {
    return null;
  }
  return { url, secret };
}

function decodeBase64(value: string) {
  const decoded = atob(value);
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

function encodeBase64(value: ArrayBuffer) {
  const bytes = new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

async function signWebhook(secret: string, webhookId: string, timestamp: string, body: string) {
  const encodedSecret = secret.replace(/^whsec_/, "");
  let keyBytes: Uint8Array;
  try {
    keyBytes = decodeBase64(encodedSecret);
  } catch {
    throw new Error("The Grok webhook secret is not valid base64.");
  }
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = new TextEncoder().encode(`${webhookId}.${timestamp}.${body}`);
  return `v1,${encodeBase64(await crypto.subtle.sign("HMAC", key, signed))}`;
}

async function setConnectorHealth(
  service: ReturnType<typeof createClient>,
  organisationId: string,
  status: "setup_required" | "connected" | "degraded" | "error",
  error: string | null,
) {
  const now = new Date().toISOString();
  await service.from("integration_health").upsert({
    organisation_id: organisationId,
    connector: "grok_bot",
    display_name: "Grok Bot",
    provider: "grok",
    status,
    last_checked_at: now,
    last_success_at: status === "connected" ? now : undefined,
    last_error: error,
    details: { billing_enabled: false, webhook_configured: status !== "setup_required" },
    updated_at: now,
  }, { onConflict: "organisation_id,connector" });
}

async function runAgent(
  body: Record<string, unknown>,
  auth: NonNullable<Awaited<ReturnType<typeof authenticate>>>,
) {
  const agentId = cleanText(body.agent_id, 64);
  if (!agentId) return json({ error: "agent_id_required" }, 422);
  const { data: agent, error: agentError } = await auth.service
    .from("ai_agents")
    .select("id,slug,name,provider,status,active,pilot")
    .eq("id", agentId)
    .eq("organisation_id", auth.profile.organisation_id)
    .maybeSingle();
  if (agentError || !agent) return json({ error: "agent_not_found" }, 404);
  if (agent.provider !== "grok" || !agent.active) {
    return json({ error: "agent_not_active", message: "Only an active Grok pilot can be run." }, 409);
  }

  const config = webhookConfig(agent.slug);
  if (!config) {
    await setConnectorHealth(auth.service, auth.profile.organisation_id, "setup_required", null);
    return json({
      error: "grok_setup_required",
      message: "Grok Bot is not connected yet. No subscription or billing change has been made.",
    }, 409);
  }

  const { data: command, error: commandError } = await auth.service
    .from("ai_agent_commands")
    .insert({
      organisation_id: auth.profile.organisation_id,
      agent_id: agent.id,
      command_type: "run_now",
      status: "dispatching",
      payload: { trigger: "manual", source: "proline_virtual_office" },
      requested_by: auth.user.id,
    })
    .select("id,requested_at")
    .single();
  if (commandError || !command) return json({ error: "command_not_saved" }, 500);

  const payload = JSON.stringify({
    event: "proline.agent.run_requested",
    command_id: command.id,
    agent: agent.slug,
    requested_at: command.requested_at,
  });
  const webhookId = `msg_${crypto.randomUUID().replaceAll("-", "")}`;
  const timestamp = Math.floor(Date.now() / 1000).toString();
  try {
    const signature = await signWebhook(config.secret, webhookId, timestamp, payload);
    const response = await fetch(config.url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "webhook-id": webhookId,
        "webhook-timestamp": timestamp,
        "webhook-signature": signature,
      },
      body: payload,
      signal: AbortSignal.timeout(12_000),
    });
    if (!response.ok) throw new Error(`Grok returned ${response.status}.`);
    const now = new Date().toISOString();
    await Promise.all([
      auth.service.from("ai_agent_commands").update({ status: "accepted", dispatched_at: now }).eq("id", command.id),
      auth.service.from("ai_agents").update({ status: "running", current_work: "Checking live jobs now", updated_at: now }).eq("id", agent.id),
      setConnectorHealth(auth.service, auth.profile.organisation_id, "connected", null),
    ]);
    return json({ accepted: true, command_id: command.id }, 202);
  } catch (error) {
    const message = error instanceof Error ? error.message.slice(0, 500) : "Grok dispatch failed.";
    await Promise.all([
      auth.service.from("ai_agent_commands").update({ status: "failed", completed_at: new Date().toISOString(), error: message }).eq("id", command.id),
      auth.service.from("ai_agents").update({ status: "degraded", last_error: message, updated_at: new Date().toISOString() }).eq("id", agent.id),
      setConnectorHealth(auth.service, auth.profile.organisation_id, "error", message),
    ]);
    return json({ error: "dispatch_failed", message }, 502);
  }
}

async function reviewProposal(
  body: Record<string, unknown>,
  auth: NonNullable<Awaited<ReturnType<typeof authenticate>>>,
) {
  const proposalId = cleanText(body.proposal_id, 64);
  const decision = body.decision === "approved" ? "approved" : body.decision === "rejected" ? "rejected" : "";
  const note = cleanText(body.note, 1000) || null;
  if (!proposalId || !decision) return json({ error: "proposal_and_decision_required" }, 422);
  const { data, error } = await auth.service
    .from("ai_action_proposals")
    .update({ status: decision, decided_by: auth.user.id, decided_at: new Date().toISOString(), decision_note: note })
    .eq("id", proposalId)
    .eq("organisation_id", auth.profile.organisation_id)
    .eq("status", "pending")
    .select("id,status")
    .maybeSingle();
  if (error) return json({ error: "proposal_update_failed" }, 500);
  if (!data) return json({ error: "proposal_not_pending" }, 409);
  return json({ ok: true, proposal: data });
}

function londonDay(value: string) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/London", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(new Date(value));
}

function isLondonBusinessDay(value: string) {
  const weekday = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/London", weekday: "short",
  }).format(new Date(value));
  return weekday !== "Sat" && weekday !== "Sun";
}

async function updateAcceptance(
  body: Record<string, unknown>,
  auth: NonNullable<Awaited<ReturnType<typeof authenticate>>>,
) {
  const agentId = cleanText(body.agent_id, 64);
  if (!agentId) return json({ error: "agent_id_required" }, 422);
  const allowedChecks = [
    "remote_run_confirmed", "correct_organisation_confirmed", "duplicate_free_confirmed",
    "approval_boundaries_confirmed", "concise_reports_confirmed",
  ] as const;
  const updates: Record<string, unknown> = { updated_at: new Date().toISOString() };
  for (const key of allowedChecks) if (typeof body[key] === "boolean") updates[key] = body[key];
  if (typeof body.note === "string") updates.approval_note = cleanText(body.note, 1000) || null;

  const { data: gate, error: gateError } = await auth.service.from("ai_agent_acceptance")
    .update(updates)
    .eq("agent_id", agentId)
    .eq("organisation_id", auth.profile.organisation_id)
    .select("*,ai_agents!inner(id,slug,name,active)")
    .maybeSingle();
  if (gateError) return json({ error: "acceptance_update_failed", message: gateError.message }, 500);
  if (!gate) return json({ error: "acceptance_not_found" }, 404);
  if (gate.gate_status !== "pilot") {
    return json({ error: "agent_not_in_pilot", message: "Only the currently supervised pilot can be reviewed." }, 409);
  }

  let runsQuery = auth.service.from("ai_agent_runs")
    .select("started_at,status")
    .eq("organisation_id", auth.profile.organisation_id)
    .eq("agent_id", agentId)
    .eq("status", "succeeded");
  if (gate.trial_started_at) runsQuery = runsQuery.gte("started_at", gate.trial_started_at);
  const { data: runs } = await runsQuery;
  const successfulDays = new Set((runs ?? [])
    .filter((run) => isLondonBusinessDay(run.started_at))
    .map((run) => londonDay(run.started_at))).size;

  if (body.finalize === true) {
    const missing = allowedChecks.filter((key) => gate[key] !== true && updates[key] !== true);
    if (successfulDays < 5 || missing.length) {
      return json({
        error: "acceptance_gate_incomplete", successful_business_days: successfulDays, missing,
        message: "Five successful business days and every safety check are required before the next bot can be activated.",
      }, 409);
    }
    const now = new Date().toISOString();
    await auth.service.from("ai_agent_acceptance").update({
      gate_status: "passed", trial_passed_at: now, approved_by: auth.user.id, updated_at: now,
    }).eq("id", gate.id);
    await auth.service.from("ai_agents").update({ pilot: false, updated_at: now }).eq("id", agentId);
    await auth.service.from("ai_agent_acceptance").update({ gate_status: "ready", updated_at: now })
      .eq("organisation_id", auth.profile.organisation_id)
      .eq("activation_order", Number(gate.activation_order) + 1)
      .eq("gate_status", "locked");
    return json({ ok: true, passed: true, successful_business_days: successfulDays });
  }
  return json({ ok: true, passed: false, successful_business_days: successfulDays, gate });
}

async function activateAgent(
  body: Record<string, unknown>,
  auth: NonNullable<Awaited<ReturnType<typeof authenticate>>>,
) {
  const agentId = cleanText(body.agent_id, 64);
  if (!agentId) return json({ error: "agent_id_required" }, 422);
  const { data: gate } = await auth.service.from("ai_agent_acceptance")
    .select("id,activation_order,gate_status,ai_agents!inner(id,slug,name,metadata)")
    .eq("agent_id", agentId)
    .eq("organisation_id", auth.profile.organisation_id)
    .maybeSingle();
  if (!gate || gate.gate_status !== "ready") return json({ error: "agent_not_ready" }, 409);
  const agent = Array.isArray(gate.ai_agents) ? gate.ai_agents[0] : gate.ai_agents;
  if (!agent) return json({ error: "agent_not_found" }, 404);

  const required = Array.isArray(agent.metadata?.required_connectors) ? agent.metadata.required_connectors : [];
  const { data: health } = await auth.service.from("integration_health")
    .select("connector,status")
    .eq("organisation_id", auth.profile.organisation_id)
    .in("connector", required);
  const states = new Map((health ?? []).map((row) => [row.connector, row.status]));
  const missing = required.filter((name: string) => !["connected", "available"].includes(states.get(name) ?? ""));
  if (missing.length) return json({ error: "connectors_not_ready", missing }, 409);

  const configured = webhookConfig(agent.slug) !== null;
  if (!configured) {
    return json({
      error: "grok_setup_required",
      message: `Create and securely connect the ${agent.name} Grok Bot before activating this trial. No billing change was made.`,
    }, 409);
  }
  const now = new Date().toISOString();
  await Promise.all([
    auth.service.from("ai_agents").update({
      active: true, pilot: true, status: configured ? "idle" : "setup_required", updated_at: now,
    }).eq("id", agentId).eq("organisation_id", auth.profile.organisation_id),
    auth.service.from("ai_agent_acceptance").update({ gate_status: "pilot", trial_started_at: now, updated_at: now }).eq("id", gate.id),
  ]);
  return json({ ok: true, activated: agent.slug, webhook_configured: configured });
}

async function recordUsage(
  body: Record<string, unknown>,
  auth: NonNullable<Awaited<ReturnType<typeof authenticate>>>,
) {
  const percent = Number(body.weekly_usage_percent);
  if (!Number.isFinite(percent) || percent < 0 || percent > 100) return json({ error: "invalid_usage_percent" }, 422);
  const reset = cleanText(body.usage_week_resets_at, 40);
  if (reset && Number.isNaN(Date.parse(reset))) return json({ error: "invalid_reset_time" }, 422);
  const now = new Date().toISOString();
  const { data, error } = await auth.service.from("ai_workforce_settings").upsert({
    organisation_id: auth.profile.organisation_id,
    target_plan: ["premium", "super", "ultra", "existing"].includes(String(body.target_plan)) ? body.target_plan : "premium",
    auto_topup_enabled: false,
    weekly_usage_percent: percent,
    usage_measured_at: now,
    usage_week_resets_at: reset || null,
    usage_note: cleanText(body.note, 1000) || null,
    updated_at: now,
  }, { onConflict: "organisation_id" }).select().single();
  if (error) return json({ error: "usage_not_saved", message: error.message }, 500);
  return json({ ok: true, settings: data });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  const auth = await authenticate(request);
  if (!auth) return json({ error: "unauthorised" }, 401);

  if (request.method === "GET") {
    const { data: agents } = await auth.service
      .from("ai_agents")
      .select("slug,active,pilot,status")
      .eq("organisation_id", auth.profile.organisation_id)
      .order("name");
    return json({ ok: true, agents: agents ?? [], configured: (agents ?? []).filter((agent) => webhookConfig(agent.slug)).map((agent) => agent.slug) });
  }
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (body.action === "run_agent") return runAgent(body, auth);
  if (body.action === "review_proposal") return reviewProposal(body, auth);
  if (body.action === "update_acceptance") return updateAcceptance(body, auth);
  if (body.action === "activate_agent") return activateAgent(body, auth);
  if (body.action === "record_usage") return recordUsage(body, auth);
  return json({ error: "unknown_action" }, 422);
});

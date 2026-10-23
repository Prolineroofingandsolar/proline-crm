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
  return json({ error: "unknown_action" }, 422);
});

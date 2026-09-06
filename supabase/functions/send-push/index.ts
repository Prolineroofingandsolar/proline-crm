import webpush from "npm:web-push@3";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
let cachedJWT: { value: string; created: number } | null = null;

async function signedInProfile(req: Request) {
  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const authorization = req.headers.get("authorization") ?? "";
  const userResponse = await fetch(`${url}/auth/v1/user`, { headers: { authorization, apikey: anon } });
  if (!userResponse.ok) return null;
  const user = await userResponse.json();
  const profileResponse = await fetch(`${url}/rest/v1/profiles?id=eq.${encodeURIComponent(user.id)}&select=id,organisation_id,role,active`, { headers: { authorization, apikey: anon } });
  const profiles = profileResponse.ok ? await profileResponse.json() : [];
  return profiles[0]?.active ? profiles[0] : null;
}

async function apnsJWT() {
  if (cachedJWT && Date.now() - cachedJWT.created < 45 * 60 * 1000) return cachedJWT.value;
  const keyID = Deno.env.get("APNS_KEY_ID");
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY")?.replace(/\\n/g, "\n");
  if (!keyID || !teamID || !privateKey) throw new Error("APNs secrets are not configured.");
  const key = await importPKCS8(privateKey, "ES256");
  const value = await new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: keyID }).setIssuer(teamID).setIssuedAt().sign(key);
  cachedJWT = { value, created: Date.now() };
  return value;
}

function notification(payload: Record<string, unknown>, role: string) {
  const event = String(payload.event ?? "");
  const name = String(payload.name ?? "").trim().slice(0, 100);
  const detail = String(payload.detail ?? "").trim().slice(0, 240);
  const recordID = String(payload.record_id ?? "").replace(/[^a-zA-Z0-9-]/g, "").slice(0, 80);
  if (event === "test" && role === "admin") return { title: "ProLine CRM", body: "Live push notifications are working.", url: "prolinecrm://dashboard" };
  if (event === "new_lead" && name && recordID) return { title: "New roofing enquiry", body: `${name}${detail ? ` — ${detail}` : ""}`, url: `prolinecrm://lead/${recordID}` };
  if (event === "team_message" && name && detail) return { title: `Message from ${name}`, body: detail, url: "prolinecrm://team" };
  if (event === "task_assigned" && detail) return { title: "New task assigned", body: detail, url: "prolinecrm://tasks" };
  if (event === "job_updated" && name && recordID) return { title: `${name} updated`, body: detail || "Open the job to see the latest update.", url: `prolinecrm://lead/${recordID}` };
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const profile = await signedInProfile(req);
  if (!profile) return json({ error: "A secure signed-in CRM account is required." }, 401);
  const payload = await req.json();
  const content = notification(payload, profile.role);
  if (!content) return json({ error: "Unsupported notification request." }, 400);
  const requestedUsers = Array.isArray(payload.user_ids) ? payload.user_ids.map(String).slice(0, 50) : [];
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  let nativeQuery = supabase.from("native_push_devices").select("id,device_token,environment,bundle_id").eq("active", true).eq("organisation_id", profile.organisation_id);
  if (requestedUsers.length) nativeQuery = nativeQuery.in("user_id", requestedUsers);
  const { data: devices, error: deviceError } = await nativeQuery;
  if (deviceError) return json({ error: deviceError.message }, 502);

  let bearer: string | null = null;
  try { if ((devices ?? []).length) bearer = await apnsJWT(); } catch (error) { console.error(error); }
  const nativeResults = await Promise.all((devices ?? []).map(async (device) => {
    if (!bearer) return false;
    const host = device.environment === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
    const response = await fetch(`${host}/3/device/${device.device_token}`, {
      method: "POST",
      headers: { authorization: `bearer ${bearer}`, "apns-topic": device.bundle_id, "apns-push-type": "alert", "apns-priority": "10", "Content-Type": "application/json" },
      body: JSON.stringify({ aps: { alert: { title: content.title, body: content.body }, sound: "default", badge: 1 }, url: content.url })
    });
    if (response.status === 410) await supabase.from("native_push_devices").delete().eq("id", device.id);
    return response.ok;
  }));

  const vapidPublic = Deno.env.get("VAPID_PUBLIC_KEY");
  const vapidPrivate = Deno.env.get("VAPID_PRIVATE_KEY");
  let webSent = 0;
  if (vapidPublic && vapidPrivate) {
    webpush.setVapidDetails(Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@prolineroofingandsolar.co.uk", vapidPublic, vapidPrivate);
    const { data: rows } = await supabase.from("push_subscriptions").select("subscription").eq("organisation_id", profile.organisation_id);
    const results = await Promise.allSettled((rows ?? []).map((row) => webpush.sendNotification(row.subscription, JSON.stringify({ ...content }))));
    webSent = results.filter((result) => result.status === "fulfilled").length;
  }
  return json({ ok: true, native_sent: nativeResults.filter(Boolean).length, native_failed: nativeResults.filter((value) => !value).length, web_sent: webSent });
});

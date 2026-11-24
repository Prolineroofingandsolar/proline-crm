import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const json = (body: unknown, status = 200) => Response.json(body, { status });
const eventPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  let eventID: string;
  try { eventID = String((await req.json()).event_id ?? ""); } catch { return json({ error: "Invalid request" }, 400); }
  if (!eventPattern.test(eventID)) return json({ error: "Invalid event" }, 400);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: claims, error: claimError } = await db.rpc("claim_lead_push", { p_event_id: eventID });
  if (claimError) { console.error("Lead notification claim failed", claimError.message); return json({ error: "Could not claim event" }, 503); }
  const event = claims?.[0];
  if (!event) return json({ ok: true, claimed: false });
  let failure: string | null = null;
  try {
    const { data: devices, error } = await db.rpc("lead_push_devices", { p_event_id: eventID });
    if (error) throw new Error("Device lookup failed");
    if (!(devices?.length)) {
      const count = await db.rpc("lead_push_delivery_count", { p_event_id: eventID });
      if (count.error || !count.data) throw new Error("No active administrator device available");
    }
    if (devices?.length) {
    const keyID = Deno.env.get("APNS_KEY_ID");
    const teamID = Deno.env.get("APNS_TEAM_ID");
    const privateKey = Deno.env.get("APNS_PRIVATE_KEY")?.replace(/\\n/g, "\n");
    if (!keyID || !teamID || !privateKey) throw new Error("APNs credentials unavailable");
    const key = await importPKCS8(privateKey, "ES256");
    const bearer = await new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: keyID }).setIssuer(teamID).setIssuedAt().sign(key);
    for (const device of devices) {
      try {
        const host = device.environment === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
        const response = await fetch(`${host}/3/device/${device.device_token}`, {
          method: "POST", headers: { authorization: `bearer ${bearer}`, "apns-topic": device.bundle_id, "apns-push-type": "alert", "apns-priority": "10", "content-type": "application/json" },
          body: JSON.stringify({ aps: { alert: { title: "New roofing enquiry", body: `${String(event.lead_name).slice(0, 100)} — ${String(event.job_type).slice(0, 100)}` }, sound: "default" }, url: `prolinecrm://lead/${encodeURIComponent(event.lead_id)}` })
        });
        if (!response.ok) { failure = `Apple returned ${response.status}`; continue; }
        const receipt = await db.rpc("mark_lead_push_delivered", { p_event_id: eventID, p_device_id: device.device_id, p_attempt: event.attempt });
        if (receipt.error) failure = "Could not record delivery receipt";
      } catch { failure = "Apple request failed"; }
    }
    }
  } catch (error) { failure = error instanceof Error ? error.message : "Delivery failed"; }
  const { error: finishError } = await db.rpc("finish_lead_push", { p_event_id: eventID, p_attempt: event.attempt, p_success: !failure, p_error: failure });
  if (finishError) { console.error("Lead notification completion failed", finishError.message); return json({ error: "Could not record result" }, 503); }
  if (failure) { console.error("Lead notification failed", { eventID, failure }); return json({ error: "Delivery failed" }, 502); }
  return json({ ok: true });
});

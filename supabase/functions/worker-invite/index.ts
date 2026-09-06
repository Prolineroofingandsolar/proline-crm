import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const encoder = new TextEncoder();
const hex = (bytes: Uint8Array) => Array.from(bytes).map((value) => value.toString(16).padStart(2, "0")).join("");
const hash = async (value: string) => hex(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value))));

const env = () => {
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) throw new Error("Supabase environment is incomplete.");
  return { url, anon, service };
};

async function authenticatedProfile(req: Request) {
  const { url, anon } = env();
  const authorization = req.headers.get("authorization") ?? "";
  const userResponse = await fetch(`${url}/auth/v1/user`, { headers: { authorization, apikey: anon } });
  if (!userResponse.ok) return null;
  const user = await userResponse.json();
  const profileResponse = await fetch(`${url}/rest/v1/profiles?id=eq.${encodeURIComponent(user.id)}&select=id,organisation_id,role,active`, { headers: { authorization, apikey: anon } });
  const rows = profileResponse.ok ? await profileResponse.json() : [];
  return rows[0] ?? null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const payload = await req.json();
    const action = String(payload.action ?? "");
    const { url, service } = env();

    if (action === "create") {
      const profile = await authenticatedProfile(req);
      if (!profile?.active || profile.role !== "admin") return json({ error: "Only an administrator can invite workers." }, 403);
      const email = String(payload.email ?? "").trim().toLowerCase();
      const role = String(payload.role ?? "worker");
      if (!/^\S+@\S+\.\S+$/.test(email)) return json({ error: "Enter the worker's email address." }, 400);
      if (!new Set(["admin", "worker", "labourer"]).has(role)) return json({ error: "Invalid worker role." }, 400);
      const raw = hex(crypto.getRandomValues(new Uint8Array(24)));
      const expiresAt = new Date(Date.now() + 7 * 86400000).toISOString();
      const insert = await fetch(`${url}/rest/v1/worker_invitations`, {
        method: "POST",
        headers: { apikey: service, authorization: `Bearer ${service}`, "Content-Type": "application/json", Prefer: "return=representation" },
        body: JSON.stringify({ organisation_id: profile.organisation_id, email, role, token_hash: await hash(raw), created_by: profile.id, expires_at: expiresAt })
      });
      if (!insert.ok) return json({ error: "The invitation could not be created." }, 502);
      const rows = await insert.json();
      return json({ id: rows[0].id, email, link: `prolinecrm://join?token=${raw}`, code: raw, expires_at: expiresAt });
    }

    if (action === "create_user") {
      const profile = await authenticatedProfile(req);
      if (!profile?.active || profile.role !== "admin") return json({ error: "Only an administrator can add users." }, 403);
      const suppliedEmail = String(payload.email ?? "").trim().toLowerCase();
      const name = String(payload.name ?? "").trim();
      const suppliedPassword = String(payload.password ?? "");
      const role = String(payload.role ?? "worker");
      const loginEnabled = suppliedEmail !== "" || suppliedPassword !== "";
      if (!name) return json({ error: "Enter the user's name." }, 400);
      if (loginEnabled && (!/^\S+@\S+\.\S+$/.test(suppliedEmail) || suppliedPassword.length < 8)) return json({ error: "For app access, enter an email and a temporary password of at least 8 characters—or leave both blank." }, 400);
      if (!new Set(["admin", "worker", "labourer"]).has(role)) return json({ error: "Invalid user role." }, 400);
      if (!loginEnabled && role === "admin") return json({ error: "An administrator needs email and password sign-in details." }, 400);
      const internalID = crypto.randomUUID();
      const email = loginEnabled ? suppliedEmail : `timesheet-${internalID}@users.prolinecrm.invalid`;
      const password = loginEnabled ? suppliedPassword : hex(crypto.getRandomValues(new Uint8Array(32)));
      const createUser = await fetch(`${url}/auth/v1/admin/users`, { method: "POST", headers: { apikey: service, authorization: `Bearer ${service}`, "Content-Type": "application/json" }, body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { name } }) });
      if (!createUser.ok) { const detail = await createUser.json().catch(() => ({})); return json({ error: String(detail.msg ?? detail.message ?? "That email already has an account.") }, 409); }
      const user = await createUser.json();
      const number = (value: unknown) => value === null || value === undefined || value === "" ? null : Number(value);
      const profileResponse = await fetch(`${url}/rest/v1/profiles`, { method: "POST", headers: { apikey: service, authorization: `Bearer ${service}`, "Content-Type": "application/json", Prefer: "return=minimal" }, body: JSON.stringify({ id: user.id, organisation_id: profile.organisation_id, email: loginEnabled ? email : null, username: loginEnabled ? email : null, name, role, active: true, day_rate: number(payload.day_rate), cis_rate: Number(payload.cis_rate ?? 20) }) });
      if (!profileResponse.ok) { await fetch(`${url}/auth/v1/admin/users/${user.id}`, { method: "DELETE", headers: { apikey: service, authorization: `Bearer ${service}` } }); return json({ error: "The user profile could not be created." }, 502); }
      return json({ ok: true, user_id: user.id, login_enabled: loginEnabled });
    }

    if (action === "accept") {
      const token = String(payload.token ?? "").trim();
      const name = String(payload.name ?? "").trim();
      const password = String(payload.password ?? "");
      if (!token || !name || password.length < 8) return json({ error: "Enter your name and a password of at least 8 characters." }, 400);
      const invitationResponse = await fetch(`${url}/rest/v1/worker_invitations?token_hash=eq.${await hash(token)}&accepted_at=is.null&expires_at=gt.${encodeURIComponent(new Date().toISOString())}&select=*`, { headers: { apikey: service, authorization: `Bearer ${service}` } });
      const invitations = invitationResponse.ok ? await invitationResponse.json() : [];
      const invitation = invitations[0];
      if (!invitation) return json({ error: "This invitation is invalid, expired or has already been used." }, 410);
      const email = String(invitation.email);
      const createUser = await fetch(`${url}/auth/v1/admin/users`, {
        method: "POST",
        headers: { apikey: service, authorization: `Bearer ${service}`, "Content-Type": "application/json" },
        body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { name } })
      });
      if (!createUser.ok) {
        const detail = await createUser.json().catch(() => ({}));
        return json({ error: String(detail.msg ?? detail.message ?? "That email already has an account.") }, 409);
      }
      const user = await createUser.json();
      const number = (value: unknown) => value === null || value === undefined || value === "" ? null : Number(value);
      const profileResponse = await fetch(`${url}/rest/v1/profiles`, {
        method: "POST",
        headers: { apikey: service, authorization: `Bearer ${service}`, "Content-Type": "application/json", Prefer: "return=minimal" },
        body: JSON.stringify({
          id: user.id, organisation_id: invitation.organisation_id, email, username: email, name,
          role: invitation.role, active: true, day_rate: number(payload.day_rate), cis_rate: Number(payload.cis_rate ?? 20),
          utr_number: String(payload.utr_number ?? "").trim() || null, bank_name: String(payload.bank_name ?? "").trim() || null,
          bank_account_number: String(payload.bank_account_number ?? "").trim() || null, bank_sort_code: String(payload.bank_sort_code ?? "").trim() || null
        })
      });
      if (!profileResponse.ok) {
        await fetch(`${url}/auth/v1/admin/users/${user.id}`, { method: "DELETE", headers: { apikey: service, authorization: `Bearer ${service}` } });
        return json({ error: "Your worker profile could not be created." }, 502);
      }
      await fetch(`${url}/rest/v1/worker_invitations?id=eq.${invitation.id}`, {
        method: "PATCH", headers: { apikey: service, authorization: `Bearer ${service}`, "Content-Type": "application/json" },
        body: JSON.stringify({ accepted_at: new Date().toISOString(), accepted_user_id: user.id })
      });
      return json({ email });
    }
    return json({ error: "Unknown action" }, 400);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Invitation request failed." }, 500);
  }
});

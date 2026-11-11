import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-supabase-api-version, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
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

// Adding someone who is already on the team fails deep inside Auth with
// "already been registered", which tells an administrator nothing. Removal is
// deliberately a soft deactivate so work history survives, so the right answer
// is almost always Restore. Look the person up first and say so.
async function existingMember(url: string, service: string, organisationID: string, email: string) {
  const headers = { apikey: service, authorization: `Bearer ${service}` };
  const response = await fetch(
    `${url}/rest/v1/profiles?organisation_id=eq.${encodeURIComponent(organisationID)}&email=eq.${encodeURIComponent(email)}&select=id,name,active`,
    { headers },
  );
  if (!response.ok) return null;
  const rows = await response.json();
  return rows[0] ?? null;
}

const alreadyOnTeam = (person: { name?: string; active?: boolean }) =>
  person.active
    ? `${person.name ?? "That person"} is already on your team.`
    : `${person.name ?? "That person"} is still here with their access removed. Open Staff & access, switch the list to "Removed access", open them and choose Restore.`;

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
      const existingInvitee = await existingMember(url, service, profile.organisation_id, email);
      if (existingInvitee) return json({ error: alreadyOnTeam(existingInvitee) }, 409);
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
      const dayRate = payload.day_rate == null || payload.day_rate === "" ? null : Number(payload.day_rate);
      const cisRate = Number(payload.cis_rate ?? 20);
      if ((dayRate !== null && (!Number.isFinite(dayRate) || dayRate < 0 || dayRate > 10000)) || ![20, 30].includes(cisRate)) return json({ error: "Enter a valid day rate and CIS rate." }, 400);
      if (loginEnabled) {
        const existing = await existingMember(url, service, profile.organisation_id, suppliedEmail);
        if (existing) return json({ error: alreadyOnTeam(existing) }, 409);
      }
      const internalID = crypto.randomUUID();
      const email = loginEnabled ? suppliedEmail : `timesheet-${internalID}@users.prolinecrm.invalid`;
      const password = loginEnabled ? suppliedPassword : hex(crypto.getRandomValues(new Uint8Array(32)));
      const createUser = await fetch(`${url}/auth/v1/admin/users`, { method: "POST", headers: { apikey: service, authorization: `Bearer ${service}`, "Content-Type": "application/json" }, body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { name } }) });
      // Auth's own wording names the other account, so it is not repeated here.
      if (!createUser.ok) return json({ error: "That email address is already used by another account." }, 409);
      const user = await createUser.json();
      const profileResponse = await fetch(`${url}/rest/v1/profiles`, { method: "POST", headers: { apikey: service, authorization: `Bearer ${service}`, "Content-Type": "application/json", Prefer: "return=minimal" }, body: JSON.stringify({ id: user.id, organisation_id: profile.organisation_id, email: loginEnabled ? email : null, username: loginEnabled ? email : null, name, role, active: true, day_rate: dayRate, cis_rate: cisRate }) });
      if (!profileResponse.ok) { await fetch(`${url}/auth/v1/admin/users/${user.id}`, { method: "DELETE", headers: { apikey: service, authorization: `Bearer ${service}` } }); return json({ error: "The user profile could not be created." }, 502); }
      return json({ ok: true, user_id: user.id, login_enabled: loginEnabled });
    }

    if (["list_staff", "update_staff", "update_staff_details", "update_staff_email", "update_staff_contact_email", "get_pay_details", "update_pay_details", "restore", "cancel_invite"].includes(action)) {
      const profile = await authenticatedProfile(req);
      if (!profile?.active || profile.role !== "admin") return json({ error: "Only administrators can manage staff." }, 403);
      const headers = { apikey: service, authorization: `Bearer ${service}`, "Content-Type": "application/json", Prefer: "return=representation" };
      const scope = `organisation_id=eq.${encodeURIComponent(profile.organisation_id)}`;
      if (action === "list_staff") {
        const [people, invites] = await Promise.all([
          fetch(`${url}/rest/v1/profiles?${scope}&select=id,name,email,contact_email,role,active,day_rate,cis_rate&order=name.asc`, { headers }),
          fetch(`${url}/rest/v1/worker_invitations?${scope}&accepted_at=is.null&select=id,email,role,expires_at,created_at&order=created_at.desc`, { headers })
        ]);
        if (!people.ok || !invites.ok) return json({ error: "Staff details could not be loaded." }, 502);
        return json({ staff: await people.json(), invitations: await invites.json() });
      }
      const id = String(action === "cancel_invite" ? payload.invitation_id ?? "" : payload.user_id ?? "");
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) return json({ error: "Invalid staff or invitation ID." }, 400);
      if (action === "cancel_invite") {
        const response = await fetch(`${url}/rest/v1/worker_invitations?id=eq.${id}&${scope}&accepted_at=is.null`, { method: "DELETE", headers });
        if (!response.ok) return json({ error: "Invitation could not be cancelled." }, 502);
        const rows = await response.json();
        return rows.length === 1 ? json({ ok: true }) : json({ error: "Invitation is no longer available." }, 404);
      }
      if (action === "get_pay_details" || action === "update_pay_details") {
        const fields = ["utr_number", "bank_name", "bank_account_number", "bank_sort_code"];
        if (action === "get_pay_details") {
          const response = await fetch(`${url}/rest/v1/profiles?id=eq.${id}&${scope}&select=${fields.join(",")}`, { headers });
          if (!response.ok) return json({ error: "Pay details could not be loaded." }, 502);
          const rows = await response.json();
          return rows.length === 1 ? json({ details: rows[0] }) : json({ error: "Employee not found in your organisation." }, 404);
        }
        if (id === profile.id) return json({ error: "Ask another administrator to change your pay details." }, 400);
        const clean = (key: string) => String(payload[key] ?? "").trim() || null;
        const utr = clean("utr_number"), bank = clean("bank_name"), account = clean("bank_account_number"), sort = clean("bank_sort_code");
        if ((utr && !/^\d{10}$/.test(utr)) || (bank && bank.length > 120) || (account && !/^\d{8}$/.test(account)) || (sort && !/^\d{2}-?\d{2}-?\d{2}$/.test(sort))) return json({ error: "Check the UTR, bank account and sort code." }, 400);
        const expected = payload.expected;
        if (!expected || typeof expected !== "object" || fields.some(key => !(key in expected) || (expected[key] !== null && typeof expected[key] !== "string"))) return json({ error: "Reload pay details before saving." }, 400);
        const response = await fetch(`${url}/rest/v1/rpc/update_staff_pay_safe`, { method: "POST", headers, body: JSON.stringify({ p_org: profile.organisation_id, p_id: id, p_expected: expected, p_details: { utr_number: utr, bank_name: bank, bank_account_number: account, bank_sort_code: sort } }) });
        if (!response.ok) return json({ error: "Pay details could not be saved." }, 502);
        return await response.json() === true ? json({ ok: true }) : json({ error: "Pay details changed or staff member is unavailable. Reload and review before saving." }, 409);
      }
      if (action === "update_staff_contact_email") {
        const email = String(payload.email ?? "").trim().toLowerCase();
        if (email && (!/^\S+@\S+\.\S+$/.test(email) || email.length > 254)) return json({ error: "Enter a valid email address." }, 400);
        const response = await fetch(`${url}/rest/v1/profiles?id=eq.${id}&${scope}`, { method: "PATCH", headers, body: JSON.stringify({ contact_email: email || null }) });
        if (!response.ok) return json({ error: "Contact email could not be saved." }, 502);
        const rows = await response.json();
        return rows.length === 1 ? json({ ok: true }) : json({ error: "Staff member not found in your organisation." }, 404);
      }
      if (action === "update_staff_email" || action === "update_staff_details") {
        if (id === profile.id) return json({ error: "Ask another administrator to update your account." }, 400);
        const lookup = await fetch(`${url}/rest/v1/profiles?id=eq.${id}&${scope}&select=id,name,email`, { headers });
        if (!lookup.ok) return json({ error: "Staff details could not be checked." }, 502);
        const rows = await lookup.json();
        if (rows.length !== 1) return json({ error: "Employee not found in your organisation." }, 404);
        if (action === "update_staff_email") {
          const email = String(payload.email ?? "").trim().toLowerCase();
          if (!rows[0].email) return json({ error: "Payroll-only staff do not have a login. Create an invitation for app access." }, 400);
          if (!/^\S+@\S+\.\S+$/.test(email) || email.length > 254) return json({ error: "Enter a valid email address." }, 400);
          if (email === String(rows[0].email).toLowerCase()) return json({ ok: true });
          const ready = await fetch(`${url}/rest/v1/rpc/staff_email_sync_ready`, { method: "POST", headers, body: "{}" });
          if (!ready.ok || await ready.json() !== true) return json({ error: "Email changes are not available until the account update is installed." }, 503);
          const updated = await fetch(`${url}/auth/v1/admin/users/${id}`, { method: "PUT", headers, body: JSON.stringify({ email, email_confirm: true }) });
          if (!updated.ok) return json({ error: "Email could not be changed. Check that it is not already in use." }, 409);
          return json({ ok: true });
        }
        const name = String(payload.name ?? "").trim();
        const role = String(payload.role ?? "");
        const rate = payload.day_rate === null || payload.day_rate === "" ? null : Number(payload.day_rate);
        const cis = Number(payload.cis_rate);
        if (!name || name.length > 120 || !["admin", "worker", "labourer"].includes(role) || (rate !== null && (!Number.isFinite(rate) || rate < 0 || rate > 10000)) || ![20, 30].includes(cis)) return json({ error: "Enter valid staff details." }, 400);
        const result = await fetch(`${url}/rest/v1/rpc/update_staff_details_safe`, { method: "POST", headers, body: JSON.stringify({ p_org: profile.organisation_id, p_id: id, p_name: name, p_role: role, p_rate: rate, p_cis: cis }) });
        if (!result.ok) {
          const detail = await result.json().catch(() => ({}));
          return json({ error: String(detail.message ?? "Staff details could not be saved.") }, 409);
        }
        return json({ ok: true });
      }
      const updates: Record<string, unknown> = {};
      if (action === "restore") {
        if (id === profile.id) return json({ error: "Choose another employee." }, 400);
        updates.active = true;
      } else {
        const role = String(payload.role ?? "");
        if (!["admin", "worker", "labourer"].includes(role)) return json({ error: "Choose a valid staff role." }, 400);
        if (id === profile.id) return json({ error: "Ask another administrator to change your role or pay settings." }, 400);
        const rate = payload.day_rate === null || payload.day_rate === "" ? null : Number(payload.day_rate);
        const cis = Number(payload.cis_rate);
        if ((rate !== null && (!Number.isFinite(rate) || rate < 0 || rate > 10000)) || ![20, 30].includes(cis)) return json({ error: "Enter a valid day rate and CIS rate." }, 400);
        updates.role = role; updates.day_rate = rate; updates.cis_rate = cis;
      }
      const response = await fetch(`${url}/rest/v1/profiles?id=eq.${id}&${scope}`, { method: "PATCH", headers, body: JSON.stringify(updates) });
      if (!response.ok) return json({ error: "Staff details could not be updated." }, 502);
      const rows = await response.json();
      return rows.length === 1 ? json({ ok: true }) : json({ error: "Employee not found in your organisation." }, 404);
    }

    if (action === "deactivate") {
      const profile = await authenticatedProfile(req);
      if (!profile?.active || profile.role !== "admin") return json({ error: "Only an administrator can remove access." }, 403);
      const userID = String(payload.user_id ?? "");
      if (!/^[0-9a-f-]{36}$/i.test(userID) || userID === profile.id) return json({ error: "Choose another employee." }, 400);
      const response = await fetch(`${url}/rest/v1/profiles?id=eq.${userID}&organisation_id=eq.${profile.organisation_id}`, {
        method: "PATCH", headers: { apikey: service, authorization: `Bearer ${service}`, "Content-Type": "application/json", Prefer: "return=representation" },
        body: JSON.stringify({ active: false })
      });
      if (!response.ok) return json({ error: "Access could not be removed." }, 502);
      const rows = await response.json();
      if (rows.length !== 1) return json({ error: "Employee not found in your organisation." }, 404);
      return json({ ok: true });
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
      const profileResponse = await fetch(`${url}/rest/v1/profiles`, {
        method: "POST",
        headers: { apikey: service, authorization: `Bearer ${service}`, "Content-Type": "application/json", Prefer: "return=minimal" },
        body: JSON.stringify({
          id: user.id, organisation_id: invitation.organisation_id, email, username: email, name,
          role: invitation.role, active: true, day_rate: null, cis_rate: Number(payload.cis_rate ?? 20),
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

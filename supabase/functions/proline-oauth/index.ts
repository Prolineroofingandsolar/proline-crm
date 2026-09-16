import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const projectUrl = Deno.env.get("SUPABASE_URL")!;
const publishableKey = Deno.env.get("SUPABASE_ANON_KEY")!;

function page() {
  const config = JSON.stringify({ projectUrl, publishableKey }).replaceAll("<", "\\u003c");
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Connect ProLine CRM</title>
  <style>
    :root { color-scheme: light; font-family: Inter, ui-sans-serif, system-ui, -apple-system, sans-serif; background:#f4f7f6; color:#13251f; }
    * { box-sizing:border-box; }
    body { margin:0; min-height:100vh; display:grid; place-items:center; padding:24px; }
    main { width:min(100%, 480px); background:white; border:1px solid #dce6e1; border-radius:18px; padding:30px; box-shadow:0 16px 50px rgba(20,45,37,.1); }
    .brand { display:flex; align-items:center; gap:12px; margin-bottom:24px; }
    .mark { width:42px; height:42px; border-radius:12px; display:grid; place-items:center; color:white; font-weight:800; background:#167d5a; }
    h1 { margin:0 0 10px; font-size:26px; line-height:1.15; }
    p { color:#53665f; line-height:1.5; }
    label { display:block; margin:14px 0 6px; font-weight:650; }
    input { width:100%; border:1px solid #b8c8c1; border-radius:10px; padding:12px; font:inherit; }
    button { border:0; border-radius:10px; padding:12px 16px; font:inherit; font-weight:700; cursor:pointer; }
    .primary { width:100%; margin-top:18px; color:white; background:#167d5a; }
    .secondary { color:#26473b; background:#e8f0ed; }
    .actions { display:flex; gap:10px; margin-top:22px; }
    .actions button { flex:1; }
    .details { margin:18px 0; padding:14px; border-radius:12px; background:#f4f7f6; }
    .details div { margin:7px 0; overflow-wrap:anywhere; }
    .error { color:#a12626; background:#fff0f0; padding:10px; border-radius:8px; }
    .fine { font-size:13px; }
    [hidden] { display:none !important; }
  </style>
</head>
<body>
<main>
  <div class="brand"><div class="mark">P</div><strong>ProLine CRM</strong></div>
  <section id="loading"><h1>Checking connection…</h1><p>Please wait.</p></section>
  <section id="error" hidden><h1>Connection problem</h1><p class="error" id="error-text"></p></section>
  <section id="login" hidden>
    <h1>Sign in to ProLine</h1>
    <p>Use your existing CRM administrator account. Your password goes directly to Supabase Auth.</p>
    <form id="login-form">
      <label for="email">Email</label><input id="email" type="email" autocomplete="username" required>
      <label for="password">Password</label><input id="password" type="password" autocomplete="current-password" required>
      <button class="primary" type="submit">Sign in</button>
    </form>
  </section>
  <section id="consent" hidden>
    <h1>Allow CRM access?</h1>
    <p><strong id="client-name">This application</strong> is asking for read-only access to your ProLine CRM.</p>
    <div class="details">
      <div><strong>It can:</strong> view jobs and tasks, find jobs, and prepare an operational plan.</div>
      <div><strong>It cannot:</strong> change CRM records, send messages, make purchases, or access MyBuilder.</div>
      <div><strong>Requested permissions:</strong> <span id="scopes"></span></div>
      <div class="fine"><strong>Return address:</strong> <span id="redirect-uri"></span></div>
    </div>
    <div class="actions"><button class="secondary" id="deny">Deny</button><button class="primary" id="approve">Allow access</button></div>
  </section>
</main>
<script type="module">
  import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
  const config = ${config};
  const supabase = createClient(config.projectUrl, config.publishableKey);
  const authorizationId = new URL(location.href).searchParams.get("authorization_id");
  const byId = (id) => document.getElementById(id);
  const show = (id) => {
    for (const name of ["loading", "error", "login", "consent"]) byId(name).hidden = name !== id;
  };
  const fail = (message) => { byId("error-text").textContent = message; show("error"); };

  async function loadConsent() {
    if (!authorizationId) return fail("The authorization request is missing or expired. Start the connection again from Grok Bot.");
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return show("login");
    const { data: profile, error: profileError } = await supabase.from("profiles")
      .select("role,active").eq("id", user.id).eq("active", true).single();
    if (profileError || !profile || profile.role !== "admin") return fail("An active ProLine administrator account is required.");
    const { data, error } = await supabase.auth.oauth.getAuthorizationDetails(authorizationId);
    if (error || !data) return fail(error?.message || "This authorization request is invalid or expired.");
    if (!("authorization_id" in data) && data.redirect_url) return location.assign(data.redirect_url);
    byId("client-name").textContent = data.client?.name || "Grok Bot";
    byId("redirect-uri").textContent = data.redirect_uri || "Not supplied";
    byId("scopes").textContent = data.scope?.split(" ").filter(Boolean).join(", ") || "Basic account access";
    show("consent");
  }

  byId("login-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    show("loading");
    const { error } = await supabase.auth.signInWithPassword({ email: byId("email").value, password: byId("password").value });
    if (error) return fail(error.message);
    await loadConsent();
  });
  byId("approve").addEventListener("click", async () => {
    byId("approve").disabled = true;
    const { data, error } = await supabase.auth.oauth.approveAuthorization(authorizationId);
    if (error || !data?.redirect_url) return fail(error?.message || "The connection could not be approved.");
    location.assign(data.redirect_url);
  });
  byId("deny").addEventListener("click", async () => {
    byId("deny").disabled = true;
    const { data, error } = await supabase.auth.oauth.denyAuthorization(authorizationId);
    if (error || !data?.redirect_url) return fail(error?.message || "The connection could not be denied.");
    location.assign(data.redirect_url);
  });
  loadConsent().catch((error) => fail(error instanceof Error ? error.message : "The connection page failed."));
</script>
</body>
</html>`;
}

Deno.serve((request) => {
  const url = new URL(request.url);
  if (request.method !== "GET") return new Response("Method not allowed", { status: 405, headers: { Allow: "GET" } });
  if (url.pathname.endsWith("/health")) {
    return Response.json({ ok: true, service: "proline-oauth" });
  }
  return new Response(page(), {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
      "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline' https://esm.sh; connect-src https://*.supabase.co; style-src 'unsafe-inline'; img-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
    },
  });
});

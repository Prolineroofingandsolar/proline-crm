import { proxyOAuth } from "../supabase/functions/proline-mcp/http.mjs";
var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// workers/proline-oauth-proxy.ts
var SUPABASE_AUTH_ORIGIN = "https://qzvdzzvkocmulcfujyea.supabase.co/auth/v1";
var LEAD_SERVICES = /* @__PURE__ */ new Set([
  "Roof Repairs",
  "New Roof Installation",
  "Flat Roofing",
  "Slate or Tile Roofing",
  "Chimney Repairs",
  "Leadwork",
  "Fascias, Soffits or Guttering",
  "Emergency Roofing",
  "Commercial Roofing",
  "Solar PV System",
  "Battery Storage",
  "EV Charging",
  "Roof Maintenance",
  "Other"
]);
var requestLog = /* @__PURE__ */ new Map();
var corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "accept, authorization, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS"
};
function consentPage() {
  const nonce = crypto.randomUUID();
  return new Response(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="robots" content="noindex,nofollow">
  <title>Connect ProLine CRM</title>
  <style>
    *{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f4f7f6;color:#13251f;font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;padding:24px}.card{width:min(100%,460px);background:#fff;border:1px solid #dce6e1;border-radius:18px;padding:32px;box-shadow:0 24px 60px rgba(19,37,31,.14)}.brand{display:flex;align-items:center;gap:12px;margin-bottom:24px}.mark{display:grid;place-items:center;width:44px;height:44px;border-radius:12px;background:#167d5a;color:#fff;font-weight:800}h1{font-size:26px;margin:0 0 12px}p{line-height:1.55;color:#53665f}.panel{margin:20px 0;padding:16px;border-radius:12px;background:#f4f7f6;font-size:14px}.panel p{margin:0 0 10px;color:#29473d}.panel p:last-child{margin:0}.actions{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:20px}button,input{width:100%;border-radius:12px;padding:13px 14px;font:inherit}button{border:0;font-weight:750;cursor:pointer}.primary{background:#167d5a;color:#fff}.secondary{background:#e8f0ed;color:#26473b}button:disabled{opacity:.55;cursor:wait}label{display:block;margin:14px 0 7px;font-weight:700}input{border:1px solid #b8c8c1}.error{background:#fff0f0;color:#9a2424;padding:14px;border-radius:12px}.small{font-size:12px;word-break:break-all}
  </style>
</head>
<body>
  <main class="card">
    <div class="brand"><div class="mark">P</div><strong>ProLine CRM</strong></div>
    <section id="content"><h1>Checking connection\u2026</h1><p>Please wait.</p></section>
  </main>
  <script type="module" nonce="${nonce}">
    import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
    const supabase = createClient("https://qzvdzzvkocmulcfujyea.supabase.co", "sb_publishable_Qwyi2uOXUrH39yGC84RUjg_2c9aAfsG");
    const authorizationId = new URLSearchParams(location.search).get("authorization_id");
    const content = document.getElementById("content");
    const htmlEscapes = {38:"&amp;",60:"&lt;",62:"&gt;",34:"&quot;",39:"&#39;"};
    const escapeHtml = (value) => String(value || "").replace(/[&<>"']/g, (c) => htmlEscapes[c.charCodeAt(0)]);
    const showError = (message) => { content.innerHTML = '<h1>Connection problem</h1><p class="error">' + escapeHtml(message) + '</p><button class="secondary" id="retry">Try again</button>'; document.getElementById("retry").onclick = load; };
    const showLogin = () => { content.innerHTML = '<h1>Sign in to ProLine</h1><p>Use your existing CRM administrator account. Your password goes directly to Supabase Auth.</p><form id="login"><label for="email">Email</label><input id="email" type="email" autocomplete="username" required><label for="password">Password</label><input id="password" type="password" autocomplete="current-password" required><button class="primary" type="submit" style="margin-top:20px">Sign in</button></form>'; document.getElementById("login").onsubmit = signIn; };
    const decide = async (decision) => { document.querySelectorAll("button").forEach((button) => button.disabled = true); const result = decision === "approve" ? await supabase.auth.oauth.approveAuthorization(authorizationId) : await supabase.auth.oauth.denyAuthorization(authorizationId); if (result.error || !result.data?.redirect_url) return showError(result.error?.message || "The authorization decision could not be completed."); location.assign(result.data.redirect_url); };
    const showConsent = (details) => { const scopes = (details.scope || "Basic account access").split(" ").filter(Boolean).join(", "); content.innerHTML = '<h1>Allow CRM access?</h1><p><strong>' + escapeHtml(details.client?.name || "Grok Bot") + '</strong> is asking to connect to your ProLine CRM.</p><div class="panel"><p><strong>It can:</strong> view jobs and tasks and prepare an operational plan. Where enabled by your administrator, tools can also record check-ins, add verified leads and submit internal actions for approval.</p><p><strong>It cannot:</strong> send customer messages, make purchases, delete records or access MyBuilder through this connector.</p><p><strong>Requested permissions:</strong> ' + escapeHtml(scopes) + '</p><p class="small"><strong>Return address:</strong> ' + escapeHtml(details.redirect_uri || "Not supplied") + '</p></div><div class="actions"><button class="secondary" id="deny">Deny</button><button class="primary" id="allow">Allow access</button></div>'; document.getElementById("deny").onclick = () => decide("deny"); document.getElementById("allow").onclick = () => decide("approve"); };
    async function signIn(event) { event.preventDefault(); const button = event.currentTarget.querySelector("button"); button.disabled = true; const email = document.getElementById("email").value; const password = document.getElementById("password").value; const { error } = await supabase.auth.signInWithPassword({ email, password }); document.getElementById("password").value = ""; if (error) return showError(error.message); await load(); }
    async function load() { if (!authorizationId) return showError("The authorization request is missing or expired. Start the connection again from Grok Bot."); content.innerHTML = '<h1>Checking connection\u2026</h1><p>Please wait.</p>'; const { data: userData } = await supabase.auth.getUser(); if (!userData.user) return showLogin(); const { data: profile, error: profileError } = await supabase.from("profiles").select("role,active").eq("id", userData.user.id).eq("active", true).single(); if (profileError || !profile || profile.role !== "admin") return showError("An active ProLine administrator account is required."); const { data, error } = await supabase.auth.oauth.getAuthorizationDetails(authorizationId); if (error || !data) return showError(error?.message || "This authorization request is invalid or expired."); if (!data.authorization_id && data.redirect_url) return location.assign(data.redirect_url); showConsent(data); }
    load().catch((error) => showError(error?.message || "The secure connection could not be loaded."));
  <\/script>
</body>
</html>`, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Security-Policy": `default-src 'none'; script-src 'nonce-${nonce}' https://esm.sh; connect-src https://qzvdzzvkocmulcfujyea.supabase.co; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'`,
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY"
    }
  });
}
__name(consentPage, "consentPage");
function json(value, status = 200, extra = {}) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", ...extra }
  });
}
__name(json, "json");
async function proxy(request, upstreamPath) {
  let grantType = "unknown";
  let hasClientId = false;
  let clientAuth = request.headers.has("authorization") ? "header" : "none";
  if (request.headers.get("content-type")?.includes("application/x-www-form-urlencoded")) {
    const form = new URLSearchParams(await request.clone().text());
    const grant = form.get("grant_type");
    if (grant === "refresh_token" || grant === "authorization_code") grantType = grant;
    hasClientId = Boolean(form.get("client_id"));
    if (form.has("client_secret")) clientAuth = "body";
  }
  const response = await proxyOAuth(request, `${SUPABASE_AUTH_ORIGIN}${upstreamPath}`);
  // Never log request bodies, token values, authorization codes, headers or URLs with queries.
  console.info(JSON.stringify({ event: "proline_oauth_response", path: new URL(request.url).pathname, grant_type: grantType, has_client_id: hasClientId, client_auth: clientAuth, status: response.status }));
  return response;
}
function clean(value, maxLength) {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}
__name(clean, "clean");
function isRateLimited(request) {
  const key = request.headers.get("cf-connecting-ip") || "unknown";
  const now = Date.now();
  const recent = (requestLog.get(key) || []).filter((time) => now - time < 10 * 60 * 1e3);
  if (recent.length >= 5) return true;
  recent.push(now);
  requestLog.set(key, recent);
  if (requestLog.size > 1e3) {
    for (const [ip, times] of requestLog) {
      if (!times.some((time) => now - time < 10 * 60 * 1e3)) requestLog.delete(ip);
    }
  }
  return false;
}
__name(isRateLimited, "isRateLimited");
async function submitLead(request, env) {
  if (isRateLimited(request)) {
    return json({ error: "Too many enquiries. Please wait and try again." }, 429, { "Retry-After": "600" });
  }
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }
  if (clean(body.company, 200)) return json({ success: true });
  const name = clean(body.name, 100);
  const phone = clean(body.phone, 40);
  const email = clean(body.email, 160);
  const postcode = clean(body.postcode, 12).toUpperCase();
  const service = clean(body.service, 80);
  const message = clean(body.message, 3e3);
  const validPhone = !phone || /^[\d\s+\-()]{7,}$/.test(phone);
  const validEmail = !email || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  const validPostcode = /^[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}$/.test(postcode);
  if (!name || !phone && !email || !validPhone || !validEmail || !validPostcode || !LEAD_SERVICES.has(service) || message.length < 10) {
    return json({ error: "Please check the enquiry details." }, 400);
  }
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
    return json({ error: "Enquiries are temporarily unavailable." }, 503);
  }
  const now = (/* @__PURE__ */ new Date()).toISOString();
  const response = await fetch(`${env.SUPABASE_URL}/rest/v1/leads`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: env.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
      Prefer: "return=minimal"
    },
    body: JSON.stringify({
      id: crypto.randomUUID(),
      name,
      phone,
      email,
      address: postcode,
      job_type: service,
      stage: "New Lead",
      source: "Website",
      notes: message,
      created_at: now,
      updated_at: now
    })
  });
  if (!response.ok) {
    console.error("Supabase lead submission failed:", response.status);
    return json({ error: "The enquiry could not be saved." }, 502);
  }
  return json({ success: true });
}
__name(submitLead, "submitLead");
var worker = {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
    const url = new URL(request.url);
    const origin = url.origin;
    if (request.method === "GET" && url.pathname === "/oauth/consent") {
      return consentPage();
    }
    if (request.method === "POST" && url.pathname === "/api/leads") return submitLead(request, env);
    if (request.method === "POST" && url.pathname === "/api/oauth/register") return proxy(request, "/oauth/clients/register");
    if (request.method === "POST" && url.pathname === "/api/oauth/token") return proxy(request, "/oauth/token");
    if (["GET", "POST"].includes(request.method) && url.pathname === "/api/oauth/userinfo") return proxy(request, "/oauth/userinfo");
    if (request.method === "GET" && url.pathname === "/.well-known/oauth-authorization-server/auth/v1") {
      const siteOrigin = `${url.protocol}//${url.host}`;
      return json(
        {
          issuer: `${siteOrigin}/auth/v1`,
          authorization_endpoint: `${SUPABASE_AUTH_ORIGIN}/oauth/authorize`,
          token_endpoint: `${siteOrigin}/api/oauth/token`,
          jwks_uri: `${SUPABASE_AUTH_ORIGIN}/.well-known/jwks.json`,
          userinfo_endpoint: `${siteOrigin}/api/oauth/userinfo`,
          registration_endpoint: `${siteOrigin}/api/oauth/register`,
          scopes_supported: ["openid", "profile", "email", "phone", "offline_access"],
          response_types_supported: ["code"],
          response_modes_supported: ["query"],
          grant_types_supported: ["authorization_code", "refresh_token"],
          subject_types_supported: ["public"],
          id_token_signing_alg_values_supported: ["RS256", "HS256", "ES256"],
          token_endpoint_auth_methods_supported: ["client_secret_basic", "client_secret_post", "none"],
          claims_supported: [
            "sub",
            "aud",
            "iss",
            "exp",
            "iat",
            "auth_time",
            "nonce",
            "email",
            "email_verified",
            "phone_number",
            "phone_number_verified",
            "name",
            "picture",
            "preferred_username",
            "updated_at"
          ],
          code_challenge_methods_supported: ["S256", "plain"]
        },
        200,
        { "Cache-Control": "public, max-age=300" }
      );
    }
    if (request.method === "GET" && url.pathname === "/.well-known/oauth-authorization-server") {
      return json(
        {
          issuer: origin,
          authorization_endpoint: `${origin}/authorize`,
          token_endpoint: `${origin}/connect/complete`,
          jwks_uri: `${SUPABASE_AUTH_ORIGIN}/.well-known/jwks.json`,
          userinfo_endpoint: `${origin}/userinfo`,
          registration_endpoint: `${origin}/register`,
          scopes_supported: ["openid", "profile", "email", "phone", "offline_access"],
          response_types_supported: ["code"],
          response_modes_supported: ["query"],
          grant_types_supported: ["authorization_code", "refresh_token"],
          subject_types_supported: ["public"],
          id_token_signing_alg_values_supported: ["RS256", "HS256", "ES256"],
          token_endpoint_auth_methods_supported: ["client_secret_basic", "client_secret_post", "none"],
          claims_supported: [
            "sub",
            "aud",
            "iss",
            "exp",
            "iat",
            "auth_time",
            "nonce",
            "email",
            "email_verified",
            "phone_number",
            "phone_number_verified",
            "name",
            "picture",
            "preferred_username",
            "updated_at"
          ],
          code_challenge_methods_supported: ["S256", "plain"]
        },
        200,
        { "Cache-Control": "public, max-age=300" }
      );
    }
    if (request.method === "GET" && url.pathname === "/authorize") {
      return Response.redirect(`${SUPABASE_AUTH_ORIGIN}/oauth/authorize${url.search}`, 302);
    }
    if (request.method === "POST" && url.pathname === "/token") return proxy(request, "/oauth/token");
    if (request.method === "POST" && url.pathname === "/connect/complete") return proxy(request, "/oauth/token");
    if (request.method === "POST" && url.pathname === "/register") return proxy(request, "/oauth/clients/register");
    if (["GET", "POST"].includes(request.method) && url.pathname === "/userinfo") return proxy(request, "/oauth/userinfo");
    if (request.method === "GET" && url.pathname === "/health") return json({ ok: true, service: "proline-oauth-proxy" });
    return json({ error: "not_found" }, 404);
  }
};
var proline_oauth_proxy_default = worker;
export {
  proline_oauth_proxy_default as default
};


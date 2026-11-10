# ProLine–Grok connection

Use one connector URL, with OAuth, on the existing **`proline`** connection:

`https://qzvdzzvkocmulcfujyea.supabase.co/functions/v1/proline-mcp/mcp`

The public health endpoint reports reachability and connector version only. It
does not prove that Grok has a valid login. Verify account access with the
authenticated `proline_status` tool. Do not create more connector aliases to
work around an expired login.

On 30 October 2026 the six installed duplicates (`proline-crm`, `proline-live`,
`proline-ready`, `proline-final`, `proline-direct`, `proline-domain`) were
uninstalled from Grok. The remaining `proline` account was authorised and both
Bruce and Rodney successfully called `proline_status` for the expected
organisation. The legacy `?v=3` on that existing plugin URL is accepted by the
same endpoint; it is not another server. Do not reinstall another variant to
change that cosmetic query string.

All seven existing CRM-related Bots were told to save the single-connector rule
in their roles and existing routines. Bruce also corrected the connector's own
stale four-tool/read-only instructions to describe the existing 14 enabled
tools, preserving its business and approval limits. A fresh successful sign-in
does not prove automatic token renewal; verify that separately after expiry.

Bruce and Stace's existing weekday routines were resumed after successful status
checks; Rodney's intake routine remained enabled. Finance and site-readiness
routines retained their existing paused state. A single enabled, one-time Grok
routine, `ProLine token renewal verification`, is scheduled for 30 October 2026
at 22:05 Europe/London. It calls only `proline_status` without reauthentication
and reports in Bruce's chat. Its result is pending, not a proven refresh success.
The temporary early-expiry diagnostic was removed and the normal OAuth response
restored; the current connected account was retained.

## Implementation

- `supabase/functions/proline-mcp/http.mjs`: stateless HTTP transport, sign-in
  discovery, protocol negotiation and error classification.
- `supabase/functions/proline-mcp/index.ts`: administrator/organisation checks and
  the existing business-tool implementations.
- `cloudflare/proline-oauth-proxy.mjs`: existing OAuth facade, consent UI and
  website enquiry routes. Tokens are still issued and rotated by Supabase.
- OAuth metadata has one canonical source on
  `oauth.prolineroofingandsolar.co.uk`. Legacy discovery redirects there.
- Existing token endpoint aliases remain valid. Public-client IDs, confidential
  authentication, PKCE parameters, token expiry and rotated refresh tokens pass
  through unchanged. Exchanges are never automatically retried.

Expired tokens return HTTP 401 and a stable `WWW-Authenticate` metadata URL.
An authenticated non-administrator receives 403. Authentication/network outages
return 503 with `Retry-After`, so a temporary failure does not falsely tell a
client to discard its login. GET and POST both enforce authentication. Supabase's
internal path rewriting is covered by the transport tests.

## Build and deployment

Run from the repository root:

```sh
node --test supabase/functions/proline-mcp/*.test.mjs cloudflare/*.test.mjs
node scripts/build-grok-connector.mjs /tmp/proline-mcp-deploy.ts
node scripts/build-grok-connector.mjs /tmp/proline-oauth-deploy.js oauth
```

Deploy the first bundle as the `proline-mcp` Edge Function's `index.ts`, retaining
the current `core.mjs`. Deploy the second as Cloudflare's `proline-oauth-proxy`.
Both bundles include the same tested OAuth proxy implementation. For CLI deploys,
the unbundled Supabase directory can also be deployed normally.

Keep `PROLINE_AGENT_CHECKINS_ENABLED` and `PROLINE_AGENT_WRITES_ENABLED` at their
existing settings. Do not change JWT expiry, disable authentication, or substitute
a service-role key for a user's OAuth token. Roll back both services to their
previous deployments if a release fails verification.

## Verification and failure diagnosis

1. Confirm public `/health` reports connector version `0.5.0`.
2. Confirm an unauthenticated GET to `/mcp` gets the sign-in challenge; it must not
   return a transport 405 or a routing 404.
3. Run `proline_status` through the actual Grok connection and confirm the expected
   organisation and existing tool list.
4. After access-token expiry, repeat without reconnecting. Confirm a successful
   `refresh_token` exchange and the tool result. A fresh login alone does not pass
   this check.

Cloudflare logs `proline_oauth_response` with path, grant type, client-ID presence,
client authentication location and HTTP status. It does not log token values,
request bodies, passwords, authorization headers or callback codes. If the client
reports renewal failure but there is no corresponding token exchange, do not
attribute it to a Supabase token rejection without further evidence.

The automated rotation test uses a controlled upstream, not Grok's private token
store or a live account. It proves forwarding and recovery behaviour in this
implementation; it does not certify Grok's own refresh implementation.

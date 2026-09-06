import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type" };
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  const base = Deno.env.get("SUPABASE_URL")!;
  const authorization = request.headers.get("authorization") ?? "";
  const client = createClient(base, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: authorization } } });
  const { data: { user } } = await client.auth.getUser();
  if (!user) return json({ error: "Sign in first." }, 401);

  const service = createClient(base, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: profile } = await service.from("profiles").select("organisation_id,role").eq("id", user.id).single();
  if (!profile || profile.role !== "admin") return json({ error: "Administrator access is required." }, 403);

  const { data: connection } = await service.from("gmail_connections")
    .select("gmail_address,enabled,last_scanned_at,created_at")
    .eq("organisation_id", profile.organisation_id)
    .eq("enabled", true)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  return json({
    connected: Boolean(connection),
    gmail_address: connection?.gmail_address ?? null,
    last_scanned_at: connection?.last_scanned_at ?? null,
  });
});

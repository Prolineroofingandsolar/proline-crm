import webpush from 'npm:web-push@3';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const VAPID_PUBLIC = Deno.env.get('VAPID_PUBLIC_KEY')!;
  const VAPID_PRIVATE = Deno.env.get('VAPID_PRIVATE_KEY')!;
  const VAPID_SUBJECT = Deno.env.get('VAPID_SUBJECT') ?? 'mailto:admin@prolineroofingandsolar.co.uk';

  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);

  const { title, body, url } = await req.json();

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: rows } = await supabase.from('push_subscriptions').select('subscription');

  const results = await Promise.allSettled(
    (rows ?? []).map(row =>
      webpush.sendNotification(row.subscription, JSON.stringify({ title, body, url: url ?? '/' }))
    )
  );

  const failed = results.filter(r => r.status === 'rejected').length;
  if (failed > 0) console.error(`${failed} push(es) failed`);

  return new Response(JSON.stringify({ ok: true, sent: results.length - failed, failed }), {
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
  });
});

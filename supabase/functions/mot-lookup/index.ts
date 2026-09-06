const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

let cachedToken: { value: string; expiresAt: number } | undefined;

async function accessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.value;
  const tokenURL = Deno.env.get('DVSA_MOT_TOKEN_URL');
  const clientID = Deno.env.get('DVSA_MOT_CLIENT_ID');
  const clientSecret = Deno.env.get('DVSA_MOT_CLIENT_SECRET');
  const scope = Deno.env.get('DVSA_MOT_SCOPE');
  if (!tokenURL || !clientID || !clientSecret || !scope) throw new Error('DVSA MOT credentials are not configured');

  const body = new URLSearchParams({ grant_type: 'client_credentials', client_id: clientID, client_secret: clientSecret, scope });
  const response = await fetch(tokenURL, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body });
  if (!response.ok) throw new Error(`DVSA authentication failed (${response.status})`);
  const result = await response.json();
  cachedToken = { value: result.access_token, expiresAt: Date.now() + Number(result.expires_in ?? 1200) * 1000 };
  return cachedToken.value;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const { registration: input } = await req.json();
    const registration = String(input ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
    if (!registration) return response({ error: 'Enter a registration number.' }, 400);

    const token = await accessToken();
    const apiKey = Deno.env.get('DVSA_MOT_API_KEY');
    if (!apiKey) throw new Error('DVSA MOT API key is not configured');
    const upstream = await fetch(`https://history.mot.api.gov.uk/v1/trade/vehicles/registration/${encodeURIComponent(registration)}`, {
      headers: { Authorization: `Bearer ${token}`, 'X-API-Key': apiKey, Accept: 'application/json' },
    });
    if (upstream.status === 404) return response({ error: 'Vehicle not found.' }, 404);
    if (!upstream.ok) return response({ error: `MOT lookup failed (${upstream.status}).` }, upstream.status);

    const vehicle = await upstream.json();
    const tests = Array.isArray(vehicle.motTests) ? vehicle.motTests : [];
    const latest = tests.find((test: Record<string, unknown>) => String(test.testResult ?? '').toUpperCase() === 'PASSED') ?? tests[0];
    return response({
      registration: vehicle.registration ?? registration,
      make: vehicle.make ?? '', model: vehicle.model ?? '', fuelType: vehicle.fuelType ?? '',
      colour: vehicle.primaryColour ?? vehicle.colour ?? '',
      firstUsedDate: vehicle.firstUsedDate ?? vehicle.registrationDate ?? '',
      motExpiryDate: latest?.expiryDate ?? '',
      odometerValue: latest?.odometerValue ? String(latest.odometerValue) : '',
      odometerUnit: latest?.odometerUnit ?? '',
      motTestCount: tests.length,
    });
  } catch (error) {
    console.error(error);
    return response({ error: error instanceof Error ? error.message : 'MOT lookup failed.' }, 500);
  }
});

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}

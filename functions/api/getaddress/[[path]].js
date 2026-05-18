export async function onRequest(context) {
  const url = new URL(context.request.url);
  const apiPath = url.pathname.replace('/api/getaddress', '');
  const targetUrl = `https://api.getaddress.io${apiPath}${url.search}`;

  const response = await fetch(targetUrl);
  const body = await response.text();

  return new Response(body, {
    status: response.status,
    headers: { 'Content-Type': 'application/json' },
  });
}

// Stateless MCP HTTP boundary. Business tools never receive an unauthenticated request.
export class ConnectionFailure extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

export const PROTOCOL_VERSIONS = ['2025-06-18', '2025-03-26', '2024-11-05'];
export const HTTP_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'accept, authorization, content-type, last-event-id, mcp-protocol-version, mcp-session-id',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Expose-Headers': 'WWW-Authenticate, MCP-Protocol-Version, MCP-Session-Id',
  'Cache-Control': 'no-store',
};

function json(body, status = 200, headers = {}) {
  return Response.json(body, { status, headers: { ...HTTP_HEADERS, ...headers } });
}

// Never retry a token exchange: refresh tokens and authorization codes can be single use.
// Preserve the response (including a rotated refresh token) and client authentication.
export async function proxyOAuth(request, endpoint, fetcher = fetch) {
  const headers = new Headers();
  for (const name of ['accept', 'authorization', 'content-type']) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }
  try {
    const response = await fetcher(endpoint, {
      method: request.method,
      headers,
      body: ['GET', 'HEAD'].includes(request.method) ? undefined : await request.arrayBuffer(),
      redirect: 'manual',
      signal: AbortSignal.timeout(15_000),
    });
    const body = await response.text();
    // Bot challenges and proxy errors must not masquerade as OAuth token responses.
    JSON.parse(body);
    return new Response(body, {
      status: response.status,
      headers: {
        ...HTTP_HEADERS,
        'Content-Type': 'application/json',
        Pragma: 'no-cache',
        ...(response.headers.has('retry-after') ? { 'Retry-After': response.headers.get('retry-after') } : {}),
      },
    });
  } catch {
    return json({ error: 'temporarily_unavailable', error_description: 'The authentication service is temporarily unavailable. Retry shortly.' }, 503, { 'Retry-After': '5' });
  }
}

export function createMcpHandler({ baseUrl, authorizationServer, scopes, authenticate, tools, callTool, asToolResult, instructions, fetcher = fetch }) {
  const resource = `${baseUrl}/mcp`;
  const metadata = `${baseUrl}/.well-known/oauth-protected-resource`;
  // Supabase removes /functions/v1 before forwarding to the function runtime.
  const resourcePaths = new Set([new URL(resource).pathname, new URL(resource).pathname.replace(/^\/functions\/v1(?=\/)/, ''), '/mcp']);
  const challenge = (invalid) => json({ error: 'unauthorized', error_description: 'Sign in to ProLine CRM.' }, 401, {
    'WWW-Authenticate': `Bearer resource_metadata="${metadata}", scope="${scopes.join(' ')}"${invalid ? ', error="invalid_token"' : ''}`,
  });
  const rpcError = (id, code, message, status = 200) => json({ jsonrpc: '2.0', id, error: { code, message } }, status);

  return async (request) => {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: HTTP_HEADERS });
    if (url.pathname.endsWith('/.well-known/oauth-protected-resource')) {
      if (request.method !== 'GET') return json({ error: 'method_not_allowed' }, 405, { Allow: 'GET, OPTIONS' });
      return json({ resource, resource_name: 'ProLine CRM', authorization_servers: [authorizationServer], scopes_supported: scopes, bearer_methods_supported: ['header'] });
    }
    // One source of authorization-server metadata; no divergent copy of its endpoints.
    if (url.pathname.endsWith('/oauth/.well-known/oauth-authorization-server')) {
      return new Response(null, { status: 307, headers: { ...HTTP_HEADERS, Location: `${authorizationServer}/.well-known/oauth-authorization-server` } });
    }
    if (url.pathname.endsWith('/health')) {
      return json({ ok: true, service: 'proline-grok-mcp', transport: 'streamable-http', connector_version: '1.0.0', protocol_versions: PROTOCOL_VERSIONS, resource, resource_metadata: metadata, authorization_server: authorizationServer, authentication_tested: false });
    }
    if (!resourcePaths.has(url.pathname)) return json({ error: 'not_found' }, 404);

    // Authenticate GET as well as POST so discovery and expired-token recovery work
    // regardless of which transport request a client sends first.
    if (!/^Bearer\s+\S+$/i.test(request.headers.get('authorization') ?? '')) return challenge(false);
    let auth;
    try {
      auth = await authenticate(request);
    } catch (error) {
      if (error instanceof ConnectionFailure && error.status === 403) return json({ error: 'forbidden', error_description: 'An active ProLine administrator is required.' }, 403);
      return json({ error: 'temporarily_unavailable', error_description: 'ProLine could not verify the connection. Retry shortly.' }, 503, { 'Retry-After': '5' });
    }
    if (!auth) return challenge(true);
    if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, { Allow: 'POST, OPTIONS' });

    let message;
    try { message = await request.json(); } catch { return rpcError(null, -32700, 'Parse error', 400); }
    if (!message || Array.isArray(message) || message.jsonrpc !== '2.0' || typeof message.method !== 'string') return rpcError(null, -32600, 'Invalid Request', 400);
    const id = message.id ?? null;
    const method = message.method;
    const params = message.params ?? {};
    if (typeof params !== 'object' || params === null || Array.isArray(params)) return rpcError(id, -32602, 'Invalid params');
    if (!('id' in message)) return new Response(null, { status: 202, headers: HTTP_HEADERS });
    if (typeof id !== 'string' && typeof id !== 'number') return rpcError(null, -32600, 'Invalid Request', 400);
    const version = request.headers.get('mcp-protocol-version');
    if (version && !PROTOCOL_VERSIONS.includes(version)) return rpcError(id, -32600, 'Unsupported MCP protocol version', 400);
    const result = (value) => json({ jsonrpc: '2.0', id, result: value });
    if (method === 'initialize') {
      if (typeof params.protocolVersion !== 'string') return rpcError(id, -32602, 'protocolVersion is required');
      return result({ protocolVersion: PROTOCOL_VERSIONS.includes(params.protocolVersion) ? params.protocolVersion : PROTOCOL_VERSIONS[0], capabilities: { tools: { listChanged: false } }, serverInfo: { name: 'proline-grok-crm', version: '1.0.0' }, instructions });
    }
    if (method === 'ping') return result({});
    if (method === 'tools/list') return result({ tools });
    if (method === 'tools/call') {
      if (typeof params.name !== 'string' || (params.arguments !== undefined && (!params.arguments || typeof params.arguments !== 'object' || Array.isArray(params.arguments)))) return rpcError(id, -32602, 'Invalid tool arguments');
      try { return result(asToolResult(await callTool(params.name, params.arguments ?? {}, auth))); }
      catch (error) { return result(asToolResult({ error: error instanceof Error ? error.message : 'The ProLine tool failed.' }, true)); }
    }
    return rpcError(id, -32601, 'Method not found');
  };
}

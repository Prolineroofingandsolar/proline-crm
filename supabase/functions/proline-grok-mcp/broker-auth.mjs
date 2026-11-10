// Internal, short-lived, request-bound credentials. The nonce must be consumed
// atomically by the database before accepting the request.
const encoder = new TextEncoder();
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const hex = bytes => Array.from(bytes, x => x.toString(16).padStart(2, '0')).join('');
const unhex = input => new Uint8Array(input.match(/../g).map(x => parseInt(x, 16)));
async function payload(userId, timestamp, nonce, method, body) {
  const hash = hex(new Uint8Array(await crypto.subtle.digest('SHA-256', body)));
  return encoder.encode(`proline-grok-v1\n${userId}\n${timestamp}\n${nonce}\n${method.toUpperCase()}\n${hash}`);
}
async function key(secret, usages) {
  return crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, usages);
}
export async function createAssertion({ secret, userId, method, body, now = Date.now(), nonce = crypto.randomUUID() }) {
  if (typeof secret !== 'string' || secret.length < 32 || !UUID.test(userId) || !UUID.test(nonce)) throw new Error('Invalid broker configuration');
  const timestamp = String(Math.floor(now / 1000));
  const signature = await crypto.subtle.sign('HMAC', await key(secret, ['sign']), await payload(userId, timestamp, nonce, method, body));
  return `${userId}.${timestamp}.${nonce}.${hex(new Uint8Array(signature))}`;
}
export async function verifyAssertion({ secret, value, method, body, consumeNonce, now = Date.now(), onFailure = () => {} }) {
  if (typeof value !== 'string' || typeof secret !== 'string' || secret.length < 32 || typeof consumeNonce !== 'function') { onFailure('configuration'); return null; }
  const [userId, timestamp, nonce, signature, ...extra] = value.split('.');
  if (extra.length || !UUID.test(userId || '') || !/^\d{10}$/.test(timestamp || '') || !UUID.test(nonce || '') || !/^[a-f0-9]{64}$/.test(signature || '')) { onFailure('format'); return null; }
  const age = Math.floor(now / 1000) - Number(timestamp);
  if (age < -5 || age > 30) { onFailure('timestamp'); return null; }
  const valid = await crypto.subtle.verify('HMAC', await key(secret, ['verify']), unhex(signature), await payload(userId, timestamp, nonce, method, body));
  if (!valid) { onFailure('signature'); return null; }
  if (!await consumeNonce(nonce)) { onFailure('nonce'); return null; }
  return userId;
}

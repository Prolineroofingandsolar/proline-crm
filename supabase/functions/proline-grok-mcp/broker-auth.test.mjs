import test from 'node:test';
import assert from 'node:assert/strict';
import { createAssertion, verifyAssertion } from './broker-auth.mjs';

test('internal assertions expire, bind each request, and cannot be replayed', async () => {
  const secret = 'secret-'.repeat(8), userId = '12345678-1234-1234-1234-123456789abc';
  const now = 1_800_000_000_000, body = new TextEncoder().encode('{"method":"tools/list"}');
  const value = await createAssertion({ secret, userId, method: 'POST', body, now });
  const seen = new Set();
  const consumeNonce = async nonce => { if (seen.has(nonce)) return false; seen.add(nonce); return true; };
  const verify = (overrides = {}) => verifyAssertion({ secret, value, method: 'POST', body, now, consumeNonce, ...overrides });
  assert.equal(await verify({ now: now + 31_000 }), null);
  assert.equal(await verify({ method: 'GET' }), null);
  assert.equal(await verify({ body: new TextEncoder().encode('{}') }), null);
  assert.equal(await verify({ secret: 'wrong-'.repeat(8) }), null);
  assert.equal(await verify(), userId);
  assert.equal(await verify(), null);
});

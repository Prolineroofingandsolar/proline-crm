import { rolldown } from 'rolldown';
import { resolve } from 'node:path';

// The dashboard editor deploys one entry file plus the existing tool implementation.
// Bundle the tested HTTP boundary into that entry instead of hand-editing live code.
const output = process.argv[2];
if (!output) throw new Error('Usage: node scripts/build-grok-connector.mjs /absolute/path/index.ts [oauth|replacement|broker]');
const entry = process.argv[3] === 'oauth'
  ? 'cloudflare/proline-oauth-proxy.mjs'
  : process.argv[3] === 'broker'
    ? 'cloudflare/proline-grok-broker.ts'
  : process.argv[3] === 'replacement'
    ? 'supabase/functions/proline-grok-mcp/index.ts'
    : 'supabase/functions/proline-mcp/index.ts';
const bundle = await rolldown({
  input: resolve(entry),
  external: (id) => id.startsWith('https:') || id.startsWith('jsr:') || id === 'cloudflare:workers' || (process.argv[3] !== 'replacement' && id.endsWith('/core.mjs')),
});
await bundle.write({ file: resolve(output), format: 'esm', sourcemap: false });
await bundle.close();
console.log(`Connector deployment entry written to ${resolve(output)}`);

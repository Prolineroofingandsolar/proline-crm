import { rolldown } from 'rolldown';
import { resolve } from 'node:path';

// The dashboard editor deploys one entry file plus the existing tool implementation.
// Bundle the tested HTTP boundary into that entry instead of hand-editing live code.
const output = process.argv[2];
if (!output) throw new Error('Usage: node scripts/build-grok-connector.mjs /absolute/path/index.ts');
const bundle = await rolldown({
  input: resolve(process.argv[3] === 'oauth' ? 'cloudflare/proline-oauth-proxy.mjs' : 'supabase/functions/proline-mcp/index.ts'),
  external: (id) => id.startsWith('https:') || id.startsWith('jsr:') || id.endsWith('/core.mjs'),
});
await bundle.write({ file: resolve(output), format: 'esm', sourcemap: false });
await bundle.close();
console.log(`Connector deployment entry written to ${resolve(output)}`);

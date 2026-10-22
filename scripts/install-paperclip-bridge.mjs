#!/usr/bin/env node

import { randomBytes } from 'node:crypto';
import {
  chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync,
  readFileSync, rmSync, writeFileSync,
} from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const home = homedir();
const configDir = resolve(home, '.config/proline');
const installDir = resolve(home, '.local/share/proline');
const stateDir = resolve(home, '.local/state/proline');
const launchAgentsDir = resolve(home, 'Library/LaunchAgents');
const configPath = resolve(configDir, 'paperclip-bridge.env');
const installedScript = resolve(installDir, 'paperclip-bridge.mjs');
const plistPath = resolve(launchAgentsDir, 'uk.co.prolineroofing.paperclip-bridge.plist');
const label = 'uk.co.prolineroofing.paperclip-bridge';

const defaults = {
  paperclipBaseUrl: 'http://127.0.0.1:3100',
  paperclipCompanyId: '2396cbbb-78c4-44b5-9541-2031b9f76c2f',
  organisationId: '00000000-0000-0000-0000-000000000001',
  supabaseUrl: 'https://qzvdzzvkocmulcfujyea.supabase.co',
  supabaseProjectRef: 'qzvdzzvkocmulcfujyea',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF6dmR6enZrb2NtdWxjZnVqeWVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg4NzIxNjUsImV4cCI6MjA5NDQ0ODE2NX0.g42AvuElukfbpgbg9Y6XImnuHQ2Po5GEaVVGMz3Siu0',
};

function escapeXml(value) {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

function readExistingToken() {
  if (!existsSync(configPath)) return '';
  const match = readFileSync(configPath, 'utf8').match(/^PAPERCLIP_BRIDGE_TOKEN=(.+)$/m);
  return match?.[1]?.trim() || '';
}

const bridgeToken = readExistingToken() || randomBytes(32).toString('hex');
mkdirSync(configDir, { recursive: true, mode: 0o700 });
mkdirSync(installDir, { recursive: true, mode: 0o700 });
mkdirSync(stateDir, { recursive: true, mode: 0o700 });
mkdirSync(launchAgentsDir, { recursive: true });

const secretTemp = mkdtempSync(resolve(tmpdir(), 'proline-bridge-'));
const secretFile = resolve(secretTemp, 'secrets.env');
writeFileSync(secretFile, [
  `PAPERCLIP_BRIDGE_TOKEN=${bridgeToken}`,
  `PAPERCLIP_ORGANISATION_ID=${defaults.organisationId}`,
  '',
].join('\n'), { mode: 0o600 });

const secretResult = spawnSync('supabase', [
  'secrets', 'set', '--project-ref', defaults.supabaseProjectRef, '--env-file', secretFile,
], { cwd: projectRoot, encoding: 'utf8' });
rmSync(secretTemp, { recursive: true, force: true });
if (secretResult.status !== 0) {
  console.error('Could not store the bridge secret in Supabase.');
  process.exit(secretResult.status || 1);
}

writeFileSync(configPath, [
  `PAPERCLIP_BASE_URL=${defaults.paperclipBaseUrl}`,
  `PAPERCLIP_COMPANY_ID=${defaults.paperclipCompanyId}`,
  `PAPERCLIP_ORGANISATION_ID=${defaults.organisationId}`,
  `SUPABASE_URL=${defaults.supabaseUrl}`,
  `SUPABASE_ANON_KEY=${defaults.supabaseAnonKey}`,
  `PAPERCLIP_BRIDGE_TOKEN=${bridgeToken}`,
  'PAPERCLIP_BRIDGE_INTERVAL_MS=15000',
  '',
].join('\n'), { mode: 0o600 });
chmodSync(configPath, 0o600);
copyFileSync(resolve(projectRoot, 'scripts/paperclip-bridge.mjs'), installedScript);
chmodSync(installedScript, 0o700);

const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${escapeXml(process.execPath)}</string>
    <string>${escapeXml(installedScript)}</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>${escapeXml(resolve(stateDir, 'paperclip-bridge.log'))}</string>
  <key>StandardErrorPath</key><string>${escapeXml(resolve(stateDir, 'paperclip-bridge.error.log'))}</string>
</dict>
</plist>
`;
writeFileSync(plistPath, plist, { mode: 0o600 });

const domain = `gui/${process.getuid()}`;
spawnSync('launchctl', ['bootout', domain, plistPath], { stdio: 'ignore' });
const launchResult = spawnSync('launchctl', ['bootstrap', domain, plistPath], { encoding: 'utf8' });
if (launchResult.status !== 0) {
  console.error('The bridge was configured but could not be started.');
  process.exit(launchResult.status || 1);
}

console.log(JSON.stringify({
  installed: true,
  service: label,
  config: configPath,
  script: installedScript,
  secretStored: true,
}));


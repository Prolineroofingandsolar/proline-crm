#!/usr/bin/env node

import { existsSync, readFileSync } from 'node:fs';
import { homedir, hostname } from 'node:os';
import { resolve } from 'node:path';

function loadEnvFile(path) {
  if (!existsSync(path)) return;
  for (const rawLine of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const split = line.indexOf('=');
    if (split < 1) continue;
    const key = line.slice(0, split).trim();
    let value = line.slice(split + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}

const envPath = resolve(process.env.PAPERCLIP_BRIDGE_ENV_FILE || `${homedir()}/.config/proline/paperclip-bridge.env`);
loadEnvFile(envPath);

const config = {
  paperclipBaseUrl: (process.env.PAPERCLIP_BASE_URL || 'http://127.0.0.1:3100').replace(/\/$/, ''),
  paperclipToken: process.env.PAPERCLIP_API_TOKEN || '',
  companyId: process.env.PAPERCLIP_COMPANY_ID || '',
  organisationId: process.env.PAPERCLIP_ORGANISATION_ID || '',
  supabaseUrl: (process.env.SUPABASE_URL || '').replace(/\/$/, ''),
  supabaseAnonKey: process.env.SUPABASE_ANON_KEY || '',
  bridgeToken: process.env.PAPERCLIP_BRIDGE_TOKEN || '',
  intervalMs: Math.max(5_000, Number(process.env.PAPERCLIP_BRIDGE_INTERVAL_MS || 15_000)),
  once: process.argv.includes('--once'),
};

for (const [key, value] of Object.entries(config)) {
  if (['paperclipToken', 'once', 'intervalMs', 'paperclipBaseUrl'].includes(key)) continue;
  if (!value) {
    console.error(`Paperclip bridge is missing ${key}. Configure ${envPath}.`);
    process.exit(1);
  }
}

const paperclipHeaders = {
  Accept: 'application/json',
  ...(config.paperclipToken ? { Authorization: `Bearer ${config.paperclipToken}` } : {}),
};

const bridgeHeaders = {
  Accept: 'application/json',
  'Content-Type': 'application/json',
  apikey: config.supabaseAnonKey,
  Authorization: `Bearer ${config.supabaseAnonKey}`,
  'x-proline-bridge-token': config.bridgeToken,
};

async function fetchJson(url, options = {}) {
  const response = await fetch(url, { ...options, signal: AbortSignal.timeout(12_000) });
  const raw = await response.text();
  let body = null;
  if (raw) {
    try { body = JSON.parse(raw); } catch { body = { error: raw.slice(0, 300) }; }
  }
  if (!response.ok) {
    const message = body?.error || body?.message || `${response.status} ${response.statusText}`;
    throw new Error(String(message).slice(0, 500));
  }
  return body;
}

function records(value, keys = []) {
  if (Array.isArray(value)) return value;
  for (const key of keys) if (Array.isArray(value?.[key])) return value[key];
  return [];
}

function safeId(value) {
  return typeof value === 'string' ? value : '';
}

function mapAgent(agent) {
  const heartbeat = agent?.runtimeConfig?.heartbeat || {};
  return {
    id: safeId(agent?.id),
    name: agent?.name,
    shortname: agent?.shortname,
    title: agent?.title,
    role: agent?.role,
    status: agent?.status,
    adapterType: agent?.adapterType || agent?.adapterConfig?.type,
    heartbeatEnabled: heartbeat.enabled === true,
    heartbeatIntervalSeconds: heartbeat.intervalSec,
    lastRunAt: agent?.lastRunAt || agent?.lastHeartbeatAt || agent?.updatedAt,
  };
}

function mapIssue(issue) {
  return {
    id: safeId(issue?.id),
    identifier: issue?.identifier,
    title: issue?.title,
    status: issue?.status,
    priority: issue?.priority,
    assigneeAgentId: issue?.assigneeAgentId,
    projectId: issue?.projectId,
    createdAt: issue?.createdAt,
    updatedAt: issue?.updatedAt,
  };
}

function mapApproval(approval) {
  return {
    id: safeId(approval?.id),
    type: approval?.type,
    status: approval?.status,
    requestedByAgentId: approval?.requestedByAgentId,
    issueId: approval?.issueId || approval?.issueIds?.[0],
    createdAt: approval?.createdAt,
    resolvedAt: approval?.resolvedAt,
  };
}

function mapActivity(item, index) {
  const issue = item?.issue || item?.target?.issue || {};
  const actor = item?.agent || item?.actorAgent || item?.actor || {};
  return {
    id: safeId(item?.id) || `${Date.parse(item?.createdAt || '') || Date.now()}-${index}`,
    action: item?.action || item?.eventType || item?.type || 'Agent activity',
    actorAgentId: item?.actorAgentId || actor?.id,
    actorName: item?.actorName || actor?.name,
    issueIdentifier: item?.issueIdentifier || issue?.identifier,
    issueTitle: item?.issueTitle || issue?.title,
    createdAt: item?.createdAt || new Date().toISOString(),
  };
}

async function readPaperclip() {
  const company = encodeURIComponent(config.companyId);
  const base = `${config.paperclipBaseUrl}/api`;
  const [agentBody, issueBody, pendingBody, revisionBody, activityBody] = await Promise.all([
    fetchJson(`${base}/companies/${company}/agents`, { headers: paperclipHeaders }),
    fetchJson(`${base}/companies/${company}/issues?status=todo,in_progress,in_review,blocked&limit=1000`, { headers: paperclipHeaders }),
    fetchJson(`${base}/companies/${company}/approvals?status=pending`, { headers: paperclipHeaders }).catch(() => []),
    fetchJson(`${base}/companies/${company}/approvals?status=revision_requested`, { headers: paperclipHeaders }).catch(() => []),
    fetchJson(`${base}/companies/${company}/audit/agent-actions?actorScope=agents&limit=100`, { headers: paperclipHeaders }).catch(() => ({ items: [] })),
  ]);

  const approvals = [
    ...records(pendingBody, ['approvals', 'items']),
    ...records(revisionBody, ['approvals', 'items']),
  ];
  return {
    organisationId: config.organisationId,
    companyId: config.companyId,
    bridgeInstance: hostname(),
    agents: records(agentBody, ['agents', 'items']).map(mapAgent),
    issues: records(issueBody, ['issues', 'items']).map(mapIssue),
    approvals: approvals.map(mapApproval),
    activity: records(activityBody, ['activity', 'items']).map(mapActivity),
  };
}

async function sendSnapshot(snapshot) {
  return fetchJson(`${config.supabaseUrl}/functions/v1/paperclip-bridge/snapshot`, {
    method: 'POST',
    headers: bridgeHeaders,
    body: JSON.stringify(snapshot),
  });
}

async function executeCommand(command) {
  const agentId = encodeURIComponent(command.paperclip_agent_id || '');
  if (!agentId) throw new Error('Agent id is missing');
  const base = `${config.paperclipBaseUrl}/api/agents/${agentId}`;
  if (command.command_type === 'wake_agent') {
    return fetchJson(`${base}/wakeup`, {
      method: 'POST',
      headers: { ...paperclipHeaders, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        source: 'on_demand',
        triggerDetail: 'manual',
        reason: 'Run requested from ProLine Virtual Office',
        idempotencyKey: `proline-${command.id}`,
        forceFreshSession: false,
      }),
    });
  }
  if (command.command_type === 'pause_agent') {
    return fetchJson(`${base}/pause`, { method: 'POST', headers: paperclipHeaders });
  }
  if (command.command_type === 'resume_agent') {
    return fetchJson(`${base}/resume`, { method: 'POST', headers: paperclipHeaders });
  }
  throw new Error('Unsupported command');
}

async function acknowledge(command, status, value) {
  const result = status === 'succeeded'
    ? { status: value?.status || 'accepted', runId: value?.id || value?.runId || null }
    : undefined;
  return fetchJson(`${config.supabaseUrl}/functions/v1/paperclip-bridge/ack`, {
    method: 'POST',
    headers: bridgeHeaders,
    body: JSON.stringify({
      organisationId: config.organisationId,
      commandId: command.id,
      status,
      result,
      error: status === 'failed' ? String(value?.message || value || 'Command failed').slice(0, 500) : undefined,
    }),
  });
}

async function processCommands() {
  const url = new URL(`${config.supabaseUrl}/functions/v1/paperclip-bridge/commands`);
  url.searchParams.set('organisation_id', config.organisationId);
  const body = await fetchJson(url, { headers: bridgeHeaders });
  const commands = records(body, ['commands']);
  for (const command of commands) {
    try {
      const result = await executeCommand(command);
      await acknowledge(command, 'succeeded', result);
      console.log(`Paperclip command ${command.command_type} completed.`);
    } catch (error) {
      await acknowledge(command, 'failed', error instanceof Error ? error : new Error('Command failed'));
      console.error(`Paperclip command ${command.command_type} failed.`);
    }
  }
}

let running = false;
async function tick() {
  if (running) return;
  running = true;
  try {
    const snapshot = await readPaperclip();
    const result = await sendSnapshot(snapshot);
    await processCommands();
    console.log(`Virtual Office synced ${result?.counts?.agents ?? 0} agents and ${result?.counts?.issues ?? 0} active tasks at ${new Date().toLocaleTimeString('en-GB')}.`);
  } catch (error) {
    console.error(`Virtual Office bridge is waiting: ${error instanceof Error ? error.message : 'unknown error'}`);
  } finally {
    running = false;
  }
}

await tick();
if (!config.once) setInterval(tick, config.intervalMs);


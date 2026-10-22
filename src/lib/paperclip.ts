// Client for a self-hosted Paperclip server (https://paperclip.ing), which runs
// the user's AI agent "company" on their Mac. Paperclip has no CORS headers, so
// the Mac app goes through the Tauri HTTP plugin and `npm run dev` goes through
// the Vite proxy at /paperclip. A browser on another device can't reach it.

import { isMacApp } from '../utils/push';

const URL_KEY = 'proline-paperclip-url';
const KEY_KEY = 'proline-paperclip-key';
const COMPANY_KEY = 'proline-paperclip-company';
export const DEFAULT_PAPERCLIP_URL = 'http://localhost:3100';

// All Paperclip routes in one place, so they're easy to fix if the API moves.
const ROUTES = {
  companies: () => '/api/companies',
  agents: (companyId: string) => `/api/companies/${companyId}/agents`,
  liveRuns: (companyId: string) => `/api/companies/${companyId}/live-runs`,
  activity: (companyId: string) => `/api/companies/${companyId}/activity`,
  issues: (companyId: string) => `/api/companies/${companyId}/issues`,
  pause: (agentId: string) => `/api/agents/${agentId}/pause`,
  resume: (agentId: string) => `/api/agents/${agentId}/resume`,
  wakeup: (agentId: string) => `/api/agents/${agentId}/wakeup`,
  comments: (issueId: string) => `/api/issues/${issueId}/comments`,
};

export type AgentStatus = 'active' | 'paused' | 'idle' | 'running' | 'error' | 'pending_approval' | 'terminated';
export type IssueStatus = 'backlog' | 'todo' | 'in_progress' | 'in_review' | 'done' | 'blocked' | 'cancelled';

export interface PaperclipCompany { id: string; name: string; }

export interface PaperclipAgent {
  id: string;
  name: string;
  role: string;
  title: string | null;
  status: AgentStatus;
  reportsTo: string | null;
  budgetMonthlyCents: number;
  spentMonthlyCents: number;
  lastHeartbeatAt: string | null;
}

export interface PaperclipRun {
  id: string;
  agentId: string;
  agentName: string;
  status: string;
  issueId: string | null;
  startedAt: string | null;
  createdAt: string;
}

export interface PaperclipActivity {
  id: string;
  actorType: string;
  actorId: string;
  action: string;
  entityType: string;
  entityId: string;
  agentId: string | null;
  details: Record<string, unknown> | null;
  createdAt: string;
}

export interface PaperclipIssue {
  id: string;
  identifier: string | null;
  title: string;
  status: IssueStatus;
  priority: string;
  assigneeAgentId: string | null;
  updatedAt: string;
}

function read(key: string) {
  try { return localStorage.getItem(key) ?? ''; } catch { return ''; }
}
function write(key: string, value: string) {
  try {
    if (value) localStorage.setItem(key, value);
    else localStorage.removeItem(key);
  } catch { /* storage unavailable */ }
}

export function getPaperclipUrl() { return read(URL_KEY) || DEFAULT_PAPERCLIP_URL; }
export function setPaperclipUrl(url: string) { write(URL_KEY, url.trim().replace(/\/+$/, '')); }
export function getPaperclipKey() { return read(KEY_KEY); }
export function setPaperclipKey(key: string) { write(KEY_KEY, key.trim()); }
export function getSavedCompanyId() { return read(COMPANY_KEY); }
export function saveCompanyId(id: string) { write(COMPANY_KEY, id); }

// Only the Mac app and local dev can reach a Paperclip running on the Mac.
export function canReachPaperclip() {
  return isMacApp() || import.meta.env.DEV;
}

export class PaperclipError extends Error {
  status: number;
  constructor(message: string, status = 0) {
    super(message);
    this.status = status;
  }
}

async function request<T>(path: string, init: { method?: string; body?: unknown } = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (init.body !== undefined) headers['Content-Type'] = 'application/json';
  const key = getPaperclipKey();
  if (key) headers.Authorization = `Bearer ${key}`;
  const options = {
    method: init.method ?? 'GET',
    headers,
    body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
  };

  let res: Response;
  try {
    if (isMacApp()) {
      const { fetch: tauriFetch } = await import('@tauri-apps/plugin-http');
      res = await tauriFetch(`${getPaperclipUrl()}${path}`, options);
    } else {
      // Vite dev server proxies /paperclip to the Paperclip URL (see vite.config.ts).
      res = await fetch(`/paperclip${path}`, options);
    }
  } catch {
    throw new PaperclipError(`Can't reach Paperclip at ${getPaperclipUrl()}. Is it running?`);
  }

  if (!res.ok) {
    let message = `Paperclip returned ${res.status}`;
    try {
      const body = await res.json();
      if (body?.error) message = typeof body.error === 'string' ? body.error : body.error.message ?? message;
    } catch { /* not JSON */ }
    if (res.status === 401 || res.status === 403) message = 'Paperclip refused access. Add a board API key in Settings → Virtual Office.';
    throw new PaperclipError(message, res.status);
  }
  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}

// Some list routes return a bare array, others wrap it.
function asList<T>(data: unknown): T[] {
  if (Array.isArray(data)) return data as T[];
  if (data && typeof data === 'object') {
    for (const key of ['items', 'issues', 'data', 'results']) {
      const value = (data as Record<string, unknown>)[key];
      if (Array.isArray(value)) return value as T[];
    }
  }
  return [];
}

export async function listCompanies() {
  return asList<PaperclipCompany>(await request(ROUTES.companies()));
}

export async function listAgents(companyId: string) {
  const agents = asList<PaperclipAgent>(await request(ROUTES.agents(companyId)));
  return agents.filter(a => a.status !== 'terminated');
}

export async function listLiveRuns(companyId: string) {
  return asList<PaperclipRun>(await request(ROUTES.liveRuns(companyId)));
}

export async function listActivity(companyId: string, agentId?: string) {
  const query = new URLSearchParams({ limit: '60' });
  if (agentId) query.set('agentId', agentId);
  return asList<PaperclipActivity>(await request(`${ROUTES.activity(companyId)}?${query}`));
}

export async function listIssues(companyId: string) {
  const query = new URLSearchParams({ status: 'backlog,todo,in_progress,in_review,blocked', limit: '200' });
  return asList<PaperclipIssue>(await request(`${ROUTES.issues(companyId)}?${query}`));
}

export function pauseAgent(agentId: string) {
  return request(ROUTES.pause(agentId), { method: 'POST', body: {} });
}

export function resumeAgent(agentId: string) {
  return request(ROUTES.resume(agentId), { method: 'POST', body: {} });
}

export function wakeAgent(agentId: string) {
  return request(ROUTES.wakeup(agentId), {
    method: 'POST',
    body: { source: 'on_demand', triggerDetail: 'manual', reason: 'Woken from ProLine Virtual Office' },
  });
}

export function createIssue(companyId: string, input: { title: string; description?: string; assigneeAgentId: string; priority?: string }) {
  return request<PaperclipIssue>(ROUTES.issues(companyId), {
    method: 'POST',
    body: { ...input, status: 'todo' },
  });
}

export function commentOnIssue(issueId: string, body: string) {
  return request(ROUTES.comments(issueId), { method: 'POST', body: { body } });
}

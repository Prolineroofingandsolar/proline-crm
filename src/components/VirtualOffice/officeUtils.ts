import type { PaperclipAgent, PaperclipActivity, PaperclipRun } from '../../lib/paperclip';

export type DeskState = 'working' | 'queued' | 'idle' | 'paused' | 'error';

export const DESK_STATE_STYLE: Record<DeskState, { dot: string; label: string; ring: string }> = {
  working: { dot: 'bg-green-500', label: 'Working', ring: 'ring-green-400' },
  queued:  { dot: 'bg-amber-400', label: 'Queued',  ring: 'ring-amber-300' },
  idle:    { dot: 'bg-gray-300',  label: 'Idle',    ring: 'ring-gray-200' },
  paused:  { dot: 'bg-red-400',   label: 'Paused',  ring: 'ring-red-300' },
  error:   { dot: 'bg-red-600',   label: 'Error',   ring: 'ring-red-500' },
};

export function deskState(agent: PaperclipAgent, run?: PaperclipRun): DeskState {
  if (agent.status === 'paused') return 'paused';
  if (agent.status === 'error') return 'error';
  if (run?.status === 'running' || agent.status === 'running') return 'working';
  if (run?.status === 'queued') return 'queued';
  return 'idle';
}

const AVATAR_COLOURS = ['bg-orange-500', 'bg-sky-500', 'bg-violet-500', 'bg-emerald-500', 'bg-rose-500', 'bg-amber-500', 'bg-teal-500', 'bg-indigo-500'];

export function avatarColour(id: string) {
  let hash = 0;
  for (const ch of id) hash = (hash * 31 + ch.charCodeAt(0)) | 0;
  return AVATAR_COLOURS[Math.abs(hash) % AVATAR_COLOURS.length];
}

export function initials(name: string) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0]?.toUpperCase()).join('') || '?';
}

export function formatCents(cents: number) {
  return `$${(cents / 100).toFixed(2)}`;
}

export function timeAgo(iso: string | null) {
  if (!iso) return 'never';
  const secs = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
  if (secs < 60) return 'just now';
  if (secs < 3600) return `${Math.floor(secs / 60)}m ago`;
  if (secs < 86400) return `${Math.floor(secs / 3600)}h ago`;
  return `${Math.floor(secs / 86400)}d ago`;
}

// Turn an audit entry like { action: "agent.paused", entityType: "agent" } into
// "You · paused · Lena", using agent names where we have them.
export function describeActivity(entry: PaperclipActivity, nameById: Map<string, string>) {
  const who = entry.actorType === 'agent' ? nameById.get(entry.actorId) ?? 'An agent'
    : entry.actorType === 'user' ? 'You' : 'Paperclip';
  const verb = entry.action.split('.').pop()?.replace(/_/g, ' ') ?? entry.action;
  const title = typeof entry.details?.title === 'string' ? `“${entry.details.title}”`
    : typeof entry.details?.identifier === 'string' ? entry.details.identifier : '';
  const target = entry.entityType === 'agent' ? nameById.get(entry.entityId) ?? 'an agent'
    : title || entry.entityType.replace(/_/g, ' ');
  return `${who} · ${verb} · ${target}`;
}

// Group agents into rooms: the top of the org chart gets its own office,
// then each of their direct reports heads a room with everyone below them.
export function buildRooms(agents: PaperclipAgent[]) {
  const ids = new Set(agents.map(a => a.id));
  const leaders = agents.filter(a => !a.reportsTo || !ids.has(a.reportsTo));
  const leaderIds = new Set(leaders.map(a => a.id));
  const childrenOf = (id: string) => agents.filter(a => a.reportsTo === id);
  const descendants = (id: string): PaperclipAgent[] =>
    childrenOf(id).flatMap(child => [child, ...descendants(child.id)]);

  const rooms: { name: string; agents: PaperclipAgent[] }[] = [];
  if (leaders.length) rooms.push({ name: leaders.length === 1 ? `${leaders[0].title || leaders[0].name}'s office` : 'Leadership', agents: leaders });

  const placed = new Set(leaderIds);
  for (const leader of leaders) {
    for (const head of childrenOf(leader.id)) {
      const team = [head, ...descendants(head.id)].filter(a => !placed.has(a.id));
      team.forEach(a => placed.add(a.id));
      if (team.length) rooms.push({ name: `${head.title || head.role || head.name} team`, agents: team });
    }
  }
  const leftovers = agents.filter(a => !placed.has(a.id));
  if (leftovers.length) rooms.push({ name: 'Open plan', agents: leftovers });
  return rooms;
}

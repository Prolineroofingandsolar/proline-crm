/* eslint-disable react-hooks/set-state-in-effect, react-hooks/purity */
import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Activity, AlertCircle, Bot, CheckCircle2, Coffee, Pause,
  Play, RefreshCw, RotateCcw, ShieldCheck, Sparkles, X,
} from 'lucide-react';
import { supabase } from '../lib/supabase';

type Agent = {
  organisation_id: string;
  paperclip_agent_id: string;
  name: string;
  shortname: string | null;
  title: string | null;
  role: string | null;
  status: string;
  adapter_type: string | null;
  heartbeat_enabled: boolean;
  heartbeat_interval_seconds: number | null;
  last_run_at: string | null;
  synced_at: string;
};

type Issue = {
  paperclip_issue_id: string;
  identifier: string | null;
  title: string;
  status: string;
  priority: string | null;
  assignee_agent_id: string | null;
  updated_at: string | null;
};

type Approval = {
  paperclip_approval_id: string;
  approval_type: string | null;
  status: string;
  requested_by_agent_id: string | null;
  created_at: string | null;
};

type ActivityRow = {
  paperclip_activity_id: string;
  action: string;
  actor_agent_id: string | null;
  actor_name: string | null;
  issue_identifier: string | null;
  issue_title: string | null;
  created_at: string;
};

type Connection = {
  connected: boolean;
  last_seen_at: string | null;
  last_success_at: string | null;
  last_error: string | null;
};

type Command = {
  id: string;
  command_type: 'wake_agent' | 'pause_agent' | 'resume_agent';
  paperclip_agent_id: string;
  status: 'pending' | 'processing' | 'succeeded' | 'failed';
  created_at: string;
  error: string | null;
};

type PendingAction = { agent: Agent; type: Command['command_type'] } | null;

const ACTIVE_ISSUE_STATUSES = new Set(['todo', 'in_progress', 'in_review', 'blocked']);

function titleCase(value: string | null | undefined) {
  return (value || 'unknown').replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function relativeTime(value: string | null | undefined) {
  if (!value) return 'Never';
  const seconds = Math.max(0, Math.round((Date.now() - new Date(value).getTime()) / 1000));
  if (seconds < 15) return 'Just now';
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

function statusStyle(status: string) {
  if (status === 'running') return 'bg-green-100 text-green-700 border-green-200';
  if (status === 'paused') return 'bg-amber-100 text-amber-700 border-amber-200';
  if (status === 'error' || status === 'blocked') return 'bg-red-100 text-red-700 border-red-200';
  if (status === 'pending_approval') return 'bg-violet-100 text-violet-700 border-violet-200';
  return 'bg-slate-100 text-slate-600 border-slate-200';
}

function priorityStyle(priority: string | null) {
  if (priority === 'urgent') return 'bg-red-100 text-red-700';
  if (priority === 'high') return 'bg-orange-100 text-orange-700';
  if (priority === 'medium') return 'bg-amber-100 text-amber-700';
  return 'bg-gray-100 text-gray-600';
}

function RobotAvatar({ name, status, large = false }: { name: string; status: string; large?: boolean }) {
  const isBruce = name.toLowerCase().includes('bruce');
  const isStace = name.toLowerCase().includes('stace');
  const primary = isBruce ? '#2563eb' : isStace ? '#f97316' : '#64748b';
  const dark = isBruce ? '#1e3a8a' : isStace ? '#9a3412' : '#334155';
  const working = status === 'running';
  const size = large ? 'w-28 h-28' : 'w-20 h-20';
  return (
    <div className={`relative ${size} shrink-0`} aria-label={`${name} robot`}>
      {working && <span className="absolute inset-0 rounded-full bg-green-400/25 animate-ping" />}
      <svg viewBox="0 0 120 120" className="relative w-full h-full drop-shadow-lg" role="img">
        <ellipse cx="60" cy="108" rx="35" ry="6" fill="#0f172a" opacity=".18" />
        <line x1="60" y1="16" x2="60" y2="6" stroke={dark} strokeWidth="4" />
        <circle cx="60" cy="5" r="4" fill={working ? '#22c55e' : '#f59e0b'} />
        <rect x="25" y="17" width="70" height="51" rx="17" fill={primary} stroke={dark} strokeWidth="4" />
        <rect x="34" y="28" width="52" height="27" rx="10" fill="#eff6ff" />
        <circle cx="49" cy="41" r="5" fill={dark} />
        <circle cx="72" cy="41" r="5" fill={dark} />
        <path d="M49 50 Q60 58 72 50" fill="none" stroke={dark} strokeWidth="3" strokeLinecap="round" />
        {isStace && <path d="M24 34 Q13 43 24 55 M96 34 Q107 43 96 55 M101 54 L107 61" fill="none" stroke="#431407" strokeWidth="4" strokeLinecap="round" />}
        <rect x="31" y="67" width="58" height="32" rx="12" fill={primary} stroke={dark} strokeWidth="4" />
        <line x1="31" y1="75" x2="17" y2="86" stroke={dark} strokeWidth="7" strokeLinecap="round" />
        <line x1="89" y1="75" x2="103" y2="86" stroke={dark} strokeWidth="7" strokeLinecap="round" />
        <line x1="47" y1="98" x2="43" y2="108" stroke={dark} strokeWidth="8" strokeLinecap="round" />
        <line x1="73" y1="98" x2="77" y2="108" stroke={dark} strokeWidth="8" strokeLinecap="round" />
        {isBruce && <><path d="M54 68 L60 75 L66 68" fill="#fff" /><path d="M60 75 L53 94 L60 99 L67 94 Z" fill="#ef4444" /></>}
        {isStace && <><rect x="48" y="74" width="24" height="19" rx="3" fill="#fff7ed" /><line x1="48" y1="80" x2="72" y2="80" stroke="#9a3412" strokeWidth="2" /><circle cx="55" cy="85" r="2" fill="#f97316" /><circle cx="65" cy="85" r="2" fill="#f97316" /></>}
        {!isBruce && !isStace && <circle cx="60" cy="83" r="8" fill="#e2e8f0" stroke={dark} strokeWidth="2" />}
      </svg>
    </div>
  );
}

export default function VirtualOfficePage() {
  const [agents, setAgents] = useState<Agent[]>([]);
  const [issues, setIssues] = useState<Issue[]>([]);
  const [approvals, setApprovals] = useState<Approval[]>([]);
  const [activity, setActivity] = useState<ActivityRow[]>([]);
  const [commands, setCommands] = useState<Command[]>([]);
  const [connection, setConnection] = useState<Connection | null>(null);
  const [selectedAgentId, setSelectedAgentId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [pendingAction, setPendingAction] = useState<PendingAction>(null);
  const [submitting, setSubmitting] = useState(false);

  const load = useCallback(async (quiet = false) => {
    if (!quiet) setLoading(true);
    const [connectionResult, agentsResult, issuesResult, approvalsResult, activityResult, commandsResult] = await Promise.all([
      supabase.from('paperclip_connection_status').select('connected,last_seen_at,last_success_at,last_error').maybeSingle(),
      supabase.from('paperclip_agents').select('*').order('name'),
      supabase.from('paperclip_issues').select('paperclip_issue_id,identifier,title,status,priority,assignee_agent_id,updated_at').order('updated_at', { ascending: false }),
      supabase.from('paperclip_approvals').select('paperclip_approval_id,approval_type,status,requested_by_agent_id,created_at').order('created_at', { ascending: false }),
      supabase.from('paperclip_activity').select('paperclip_activity_id,action,actor_agent_id,actor_name,issue_identifier,issue_title,created_at').order('created_at', { ascending: false }).limit(100),
      supabase.from('paperclip_commands').select('id,command_type,paperclip_agent_id,status,created_at,error').order('created_at', { ascending: false }).limit(30),
    ]);

    const firstError = [connectionResult.error, agentsResult.error, issuesResult.error, approvalsResult.error, activityResult.error, commandsResult.error].find(Boolean);
    if (firstError) {
      setError(firstError.message.includes('does not exist') ? 'The Virtual Office database upgrade has not been installed yet.' : firstError.message);
    } else {
      setError('');
      setConnection(connectionResult.data as Connection | null);
      setAgents((agentsResult.data ?? []) as Agent[]);
      setIssues((issuesResult.data ?? []) as Issue[]);
      setApprovals((approvalsResult.data ?? []) as Approval[]);
      setActivity((activityResult.data ?? []) as ActivityRow[]);
      setCommands((commandsResult.data ?? []) as Command[]);
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    void load();
    const channel = supabase.channel('proline-virtual-office')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'paperclip_connection_status' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'paperclip_agents' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'paperclip_issues' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'paperclip_approvals' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'paperclip_activity' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'paperclip_commands' }, () => void load(true))
      .subscribe();
    const timer = window.setInterval(() => void load(true), 20_000);
    return () => { window.clearInterval(timer); void supabase.removeChannel(channel); };
  }, [load]);

  useEffect(() => {
    if (!selectedAgentId && agents[0]) setSelectedAgentId(agents[0].paperclip_agent_id);
    if (selectedAgentId && !agents.some((agent) => agent.paperclip_agent_id === selectedAgentId)) {
      setSelectedAgentId(agents[0]?.paperclip_agent_id ?? null);
    }
  }, [agents, selectedAgentId]);

  const selectedAgent = agents.find((agent) => agent.paperclip_agent_id === selectedAgentId) ?? null;
  const isFresh = Boolean(connection?.last_seen_at && Date.now() - new Date(connection.last_seen_at).getTime() < 75_000);
  const online = Boolean(connection?.connected && isFresh);
  const activeIssues = issues.filter((issue) => ACTIVE_ISSUE_STATUSES.has(issue.status));
  const pendingApprovals = approvals.filter((approval) => ['pending', 'revision_requested'].includes(approval.status));
  const selectedIssues = selectedAgent
    ? activeIssues.filter((issue) => issue.assignee_agent_id === selectedAgent.paperclip_agent_id)
    : activeIssues;
  const selectedActivity = selectedAgent
    ? activity.filter((row) => row.actor_agent_id === selectedAgent.paperclip_agent_id || row.actor_name === selectedAgent.name).slice(0, 15)
    : activity.slice(0, 15);

  const commandByAgent = useMemo(() => {
    const map = new Map<string, Command>();
    for (const command of commands) {
      if (!map.has(command.paperclip_agent_id) && ['pending', 'processing'].includes(command.status)) map.set(command.paperclip_agent_id, command);
    }
    return map;
  }, [commands]);

  async function confirmAction() {
    if (!pendingAction) return;
    setSubmitting(true);
    const { error: insertError } = await supabase.from('paperclip_commands').insert({
      command_type: pendingAction.type,
      paperclip_agent_id: pendingAction.agent.paperclip_agent_id,
      payload: {},
    });
    if (insertError) {
      setNotice(`Could not queue command: ${insertError.message}`);
    } else {
      const label = pendingAction.type === 'wake_agent' ? 'Run' : pendingAction.type === 'pause_agent' ? 'Pause' : 'Resume';
      setNotice(`${label} request queued for ${pendingAction.agent.name}.`);
      void load(true);
    }
    setSubmitting(false);
    setPendingAction(null);
    window.setTimeout(() => setNotice(''), 5000);
  }

  if (loading && !agents.length) {
    return <div className="h-full grid place-items-center bg-slate-50"><RefreshCw className="animate-spin text-orange-500" size={28} /></div>;
  }

  return (
    <div className="h-full overflow-y-auto bg-slate-50 p-3 sm:p-5 lg:p-6">
      <div className="max-w-[1500px] mx-auto space-y-4">
        <section className="relative overflow-hidden rounded-3xl bg-slate-900 text-white p-5 sm:p-7 shadow-xl">
          <div className="absolute -right-16 -top-16 w-64 h-64 rounded-full bg-orange-500/15" />
          <div className="absolute right-36 -bottom-24 w-48 h-48 rounded-full bg-blue-500/10" />
          <div className="relative flex flex-col lg:flex-row lg:items-center gap-5">
            <div className="flex-1">
              <div className="flex items-center gap-2 text-orange-300 text-xs font-bold uppercase tracking-[.2em]"><Sparkles size={15} /> Live operations</div>
              <h2 className="mt-2 text-2xl sm:text-3xl font-black">ProLine Virtual Office</h2>
              <p className="mt-2 text-sm text-slate-300 max-w-2xl">Your Paperclip team now lives inside the CRM. Watch work move, inspect tasks and approve agent controls without opening another dashboard.</p>
            </div>
            <div className="grid grid-cols-3 gap-2 sm:gap-3">
              <Metric value={agents.length} label="Agents" />
              <Metric value={activeIssues.length} label="Live tasks" />
              <Metric value={pendingApprovals.length} label="Approvals" alert={pendingApprovals.length > 0} />
            </div>
            <div className="flex items-center gap-3 rounded-2xl bg-white/10 border border-white/10 px-4 py-3 min-w-52">
              <span className={`w-3 h-3 rounded-full ${online ? 'bg-green-400 shadow-[0_0_15px_#4ade80]' : 'bg-amber-400'}`} />
              <div>
                <p className="text-sm font-bold">{online ? 'Bridge online' : 'Bridge waiting'}</p>
                <p className="text-xs text-slate-400">Last sync {relativeTime(connection?.last_seen_at)}</p>
              </div>
              <button onClick={() => void load()} title="Refresh view" className="ml-auto p-2 rounded-lg hover:bg-white/10"><RefreshCw size={16} /></button>
            </div>
          </div>
        </section>

        {error && (
          <div className="flex items-start gap-3 rounded-2xl border border-red-200 bg-red-50 p-4 text-red-800">
            <AlertCircle size={20} className="mt-0.5 shrink-0" />
            <div><p className="font-bold">Virtual Office needs attention</p><p className="text-sm mt-0.5">{error}</p></div>
          </div>
        )}
        {notice && <div className="rounded-xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm font-medium text-blue-800">{notice}</div>}

        <section className="rounded-3xl border border-slate-200 bg-white shadow-sm overflow-hidden">
          <div className="px-5 py-4 border-b border-slate-100 flex items-center gap-2">
            <Bot size={19} className="text-orange-500" />
            <h3 className="font-extrabold text-slate-800">The office</h3>
            <span className="ml-auto text-xs text-slate-400">Select a bot to inspect its desk</span>
          </div>
          <div className="relative bg-gradient-to-b from-sky-50 to-slate-100 p-4 sm:p-6">
            <div className="absolute inset-x-0 bottom-0 h-24 bg-[linear-gradient(90deg,rgba(148,163,184,.18)_1px,transparent_1px),linear-gradient(rgba(148,163,184,.18)_1px,transparent_1px)] bg-[size:28px_28px]" />
            {agents.length ? (
              <div className="relative grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4">
                {agents.map((agent) => {
                  const taskCount = activeIssues.filter((issue) => issue.assignee_agent_id === agent.paperclip_agent_id).length;
                  const queued = commandByAgent.get(agent.paperclip_agent_id);
                  const selected = selectedAgentId === agent.paperclip_agent_id;
                  return (
                    <article key={agent.paperclip_agent_id} onClick={() => setSelectedAgentId(agent.paperclip_agent_id)}
                      className={`relative cursor-pointer rounded-3xl border-2 p-4 transition-all ${selected ? 'border-orange-400 bg-white shadow-xl -translate-y-0.5' : 'border-white bg-white/80 hover:border-orange-200 hover:bg-white shadow-sm'}`}>
                      <div className="flex gap-4">
                        <RobotAvatar name={agent.name} status={agent.status} large />
                        <div className="min-w-0 flex-1 pt-2">
                          <div className="flex items-start gap-2">
                            <div className="min-w-0 flex-1"><h4 className="font-black text-lg text-slate-900 truncate">{agent.name}</h4><p className="text-xs text-slate-500 truncate">{agent.title || titleCase(agent.role)}</p></div>
                            <span className={`shrink-0 border text-[10px] font-bold px-2 py-1 rounded-full ${statusStyle(agent.status)}`}>{titleCase(agent.status)}</span>
                          </div>
                          <div className="mt-4 grid grid-cols-2 gap-2">
                            <DeskStat label="Open tasks" value={String(taskCount)} />
                            <DeskStat label="Last active" value={relativeTime(agent.last_run_at)} />
                          </div>
                        </div>
                      </div>
                      <div className="mt-3 h-12 rounded-xl bg-amber-100 border-t-4 border-amber-700/50 flex items-center justify-center gap-2 text-xs font-bold text-amber-900">
                        <Coffee size={14} /> {queued ? `${titleCase(queued.command_type.replace('_agent', ''))} queued` : agent.status === 'running' ? 'Working now' : 'Desk ready'}
                      </div>
                    </article>
                  );
                })}
              </div>
            ) : (
              <div className="relative py-16 text-center"><Bot size={42} className="mx-auto text-slate-300" /><p className="mt-3 font-bold text-slate-600">No agents have arrived yet</p><p className="text-sm text-slate-400">Start the private bridge and they will appear here automatically.</p></div>
            )}
          </div>
        </section>

        {selectedAgent && (
          <section className="grid grid-cols-1 xl:grid-cols-[1.05fr_1.35fr_.9fr] gap-4">
            <div className="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm">
              <div className="flex items-center gap-3"><RobotAvatar name={selectedAgent.name} status={selectedAgent.status} /><div><p className="text-xs text-slate-400 font-bold uppercase tracking-wider">Selected agent</p><h3 className="text-xl font-black text-slate-900">{selectedAgent.name}</h3><p className="text-sm text-slate-500">{selectedAgent.title || titleCase(selectedAgent.role)}</p></div></div>
              <div className="mt-5 space-y-2 text-sm">
                <InfoRow label="Status" value={titleCase(selectedAgent.status)} />
                <InfoRow label="Model runner" value={titleCase(selectedAgent.adapter_type)} />
                <InfoRow label="Automatic runs" value={selectedAgent.heartbeat_enabled ? `Every ${Math.round((selectedAgent.heartbeat_interval_seconds || 0) / 60)} min` : 'Off'} />
                <InfoRow label="Last activity" value={relativeTime(selectedAgent.last_run_at)} />
              </div>
              <div className="mt-5 grid grid-cols-2 gap-2">
                <button disabled={!online || Boolean(commandByAgent.get(selectedAgent.paperclip_agent_id))}
                  onClick={() => setPendingAction({ agent: selectedAgent, type: 'wake_agent' })}
                  className="col-span-2 flex items-center justify-center gap-2 rounded-xl bg-orange-600 hover:bg-orange-700 disabled:bg-slate-200 disabled:text-slate-400 text-white font-bold text-sm py-3 transition-colors"><Play size={16} /> Run now</button>
                {selectedAgent.status === 'paused' ? (
                  <button disabled={!online || Boolean(commandByAgent.get(selectedAgent.paperclip_agent_id))}
                    onClick={() => setPendingAction({ agent: selectedAgent, type: 'resume_agent' })}
                    className="col-span-2 flex items-center justify-center gap-2 rounded-xl border border-green-200 bg-green-50 hover:bg-green-100 disabled:opacity-50 text-green-700 font-bold text-sm py-3"><RotateCcw size={16} /> Resume agent</button>
                ) : (
                  <button disabled={!online || Boolean(commandByAgent.get(selectedAgent.paperclip_agent_id))}
                    onClick={() => setPendingAction({ agent: selectedAgent, type: 'pause_agent' })}
                    className="col-span-2 flex items-center justify-center gap-2 rounded-xl border border-amber-200 bg-amber-50 hover:bg-amber-100 disabled:opacity-50 text-amber-700 font-bold text-sm py-3"><Pause size={16} /> Pause agent</button>
                )}
              </div>
              <div className="mt-4 flex gap-2 text-xs text-slate-500 bg-slate-50 rounded-xl p-3"><ShieldCheck size={16} className="text-green-600 shrink-0" /> Controls require confirmation and are executed by the private office bridge.</div>
            </div>

            <div className="rounded-3xl border border-slate-200 bg-white shadow-sm overflow-hidden">
              <div className="px-5 py-4 border-b border-slate-100 flex items-center gap-2"><CheckCircle2 size={18} className="text-blue-600" /><h3 className="font-extrabold text-slate-800">{selectedAgent.name}&apos;s live tasks</h3><span className="ml-auto bg-slate-100 text-slate-600 text-xs font-bold px-2 py-1 rounded-full">{selectedIssues.length}</span></div>
              <div className="divide-y divide-slate-100 max-h-[430px] overflow-y-auto">
                {selectedIssues.length ? selectedIssues.map((issue) => (
                  <div key={issue.paperclip_issue_id} className="px-5 py-4">
                    <div className="flex items-start gap-3">
                      <span className={`mt-0.5 text-[10px] font-black uppercase px-2 py-1 rounded-md ${priorityStyle(issue.priority)}`}>{issue.priority || 'normal'}</span>
                      <div className="min-w-0 flex-1"><p className="text-sm font-bold text-slate-800">{issue.title}</p><div className="mt-1 flex flex-wrap gap-2 text-xs text-slate-400"><span>{issue.identifier || 'Task'}</span><span>•</span><span>{titleCase(issue.status)}</span><span>•</span><span>{relativeTime(issue.updated_at)}</span></div></div>
                    </div>
                  </div>
                )) : <div className="py-14 text-center text-sm text-slate-400">No active tasks assigned to this agent.</div>}
              </div>
            </div>

            <div className="rounded-3xl border border-slate-200 bg-white shadow-sm overflow-hidden">
              <div className="px-5 py-4 border-b border-slate-100 flex items-center gap-2"><Activity size={18} className="text-green-600" /><h3 className="font-extrabold text-slate-800">Recent movement</h3></div>
              <div className="p-4 space-y-4 max-h-[430px] overflow-y-auto">
                {selectedActivity.length ? selectedActivity.map((row) => (
                  <div key={row.paperclip_activity_id} className="flex gap-3">
                    <div className="flex flex-col items-center"><span className="mt-1 w-2.5 h-2.5 rounded-full bg-green-500 ring-4 ring-green-100" /><span className="w-px flex-1 bg-slate-200 mt-2" /></div>
                    <div className="pb-3 min-w-0"><p className="text-sm font-semibold text-slate-700">{titleCase(row.action)}</p>{row.issue_title && <p className="text-xs text-slate-500 mt-0.5 line-clamp-2">{row.issue_identifier ? `${row.issue_identifier} · ` : ''}{row.issue_title}</p>}<p className="text-[11px] text-slate-400 mt-1">{relativeTime(row.created_at)}</p></div>
                  </div>
                )) : <div className="py-12 text-center text-sm text-slate-400">No recent activity yet.</div>}
              </div>
            </div>
          </section>
        )}

        {pendingApprovals.length > 0 && (
          <section className="rounded-3xl border border-violet-200 bg-violet-50 p-5">
            <div className="flex items-center gap-2"><ShieldCheck size={20} className="text-violet-700" /><h3 className="font-black text-violet-900">Decisions waiting for you</h3><span className="ml-auto bg-violet-700 text-white text-xs font-bold px-2.5 py-1 rounded-full">{pendingApprovals.length}</span></div>
            <div className="mt-3 grid sm:grid-cols-2 xl:grid-cols-3 gap-3">
              {pendingApprovals.map((approval) => {
                const agent = agents.find((item) => item.paperclip_agent_id === approval.requested_by_agent_id);
                return <div key={approval.paperclip_approval_id} className="rounded-2xl border border-violet-200 bg-white p-4"><p className="font-bold text-slate-800">{titleCase(approval.approval_type)} approval</p><p className="text-xs text-slate-500 mt-1">Requested by {agent?.name || 'an agent'} · {relativeTime(approval.created_at)}</p><p className="mt-3 text-xs font-bold text-violet-700">{titleCase(approval.status)}</p></div>;
              })}
            </div>
          </section>
        )}
      </div>

      {pendingAction && (
        <div className="fixed inset-0 z-[100] bg-slate-950/60 grid place-items-center p-4" onMouseDown={(event) => { if (event.target === event.currentTarget) setPendingAction(null); }}>
          <div className="w-full max-w-md rounded-3xl bg-white shadow-2xl p-6">
            <div className="flex items-start gap-4"><RobotAvatar name={pendingAction.agent.name} status={pendingAction.agent.status} /><div className="flex-1"><p className="text-xs text-orange-600 font-black uppercase tracking-wider">Confirm agent control</p><h3 className="text-xl font-black text-slate-900 mt-1">{titleCase(pendingAction.type.replace('_agent', ''))} {pendingAction.agent.name}?</h3><p className="text-sm text-slate-500 mt-2">This request will be recorded in ProLine and executed by the private Paperclip bridge.</p></div><button onClick={() => setPendingAction(null)} className="p-1 text-slate-400 hover:text-slate-700"><X size={20} /></button></div>
            <div className="mt-6 flex gap-3"><button onClick={() => setPendingAction(null)} className="flex-1 rounded-xl border border-slate-200 py-3 text-sm font-bold text-slate-600">Cancel</button><button disabled={submitting} onClick={() => void confirmAction()} className="flex-1 rounded-xl bg-orange-600 hover:bg-orange-700 disabled:opacity-50 py-3 text-sm font-bold text-white">{submitting ? 'Queuing…' : 'Confirm'}</button></div>
          </div>
        </div>
      )}
    </div>
  );
}

function Metric({ value, label, alert = false }: { value: number; label: string; alert?: boolean }) {
  return <div className={`rounded-2xl border px-3 py-3 text-center min-w-20 ${alert ? 'bg-violet-500/20 border-violet-300/30' : 'bg-white/10 border-white/10'}`}><p className="text-xl font-black">{value}</p><p className="text-[10px] uppercase tracking-wider text-slate-300">{label}</p></div>;
}

function DeskStat({ label, value }: { label: string; value: string }) {
  return <div className="rounded-xl bg-slate-50 px-2 py-2"><p className="text-[10px] text-slate-400 uppercase font-bold">{label}</p><p className="text-xs font-black text-slate-700 truncate">{value}</p></div>;
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return <div className="flex items-center justify-between gap-4 border-b border-slate-100 pb-2"><span className="text-slate-400">{label}</span><span className="font-bold text-slate-700 text-right">{value}</span></div>;
}

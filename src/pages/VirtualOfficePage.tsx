/* eslint-disable react-hooks/set-state-in-effect, react-hooks/purity */
import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Activity, AlertCircle, Bot, Check, CheckCircle2, ChevronDown, Cloud,
  ExternalLink, Play, Plug, RefreshCw, ShieldCheck, Sparkles, Wallet, X,
} from 'lucide-react';
import { supabase } from '../lib/supabase';

type Agent = {
  id: string; slug: string; name: string; title: string; provider: string;
  status: string; active: boolean; pilot: boolean; colour: string; accessory: string;
  schedule_label: string | null; current_work: string | null; next_run_at: string | null;
  last_checkin_at: string | null; last_success_at: string | null; last_error: string | null;
};

type Finding = {
  id: string; bucket: 'urgent' | 'waiting' | 'money' | 'approval'; title: string;
  detail: string | null; severity: string; sourceId: string | null;
};

type AgentRun = {
  id: string; agent_id: string; status: string; summary: string | null; items: unknown;
  item_count: number; error: string | null; trigger_type: string; started_at: string; finished_at: string | null;
};

type Proposal = {
  id: string; agent_id: string; category: string; title: string; summary: string;
  risk_level: string; status: string; created_at: string;
};

type Connector = {
  connector: string; display_name: string; provider: string; status: string;
  last_checked_at: string | null; last_success_at: string | null; last_error: string | null;
};

type PaperclipConnection = {
  connected: boolean; last_seen_at: string | null; last_success_at: string | null; last_error: string | null;
};

type PaperclipIssue = {
  paperclip_issue_id: string; identifier: string | null; title: string; status: string;
  priority: string | null; updated_at: string | null;
};

const ACTIVE_ISSUE_STATUSES = new Set(['todo', 'in_progress', 'in_review', 'blocked']);
const BUCKETS = new Set(['urgent', 'waiting', 'money', 'approval']);

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
  if (['connected', 'idle', 'succeeded', 'available'].includes(status)) return 'bg-green-100 text-green-700 border-green-200';
  if (status === 'running') return 'bg-blue-100 text-blue-700 border-blue-200';
  if (['setup_required', 'planned', 'paused'].includes(status)) return 'bg-amber-100 text-amber-700 border-amber-200';
  if (['error', 'degraded', 'failed'].includes(status)) return 'bg-red-100 text-red-700 border-red-200';
  return 'bg-slate-100 text-slate-600 border-slate-200';
}

function normaliseFinding(value: unknown, runId: string, index: number): Finding | null {
  if (!value || typeof value !== 'object') return null;
  const row = value as Record<string, unknown>;
  const title = typeof row.title === 'string' ? row.title.trim().slice(0, 180) : '';
  if (!title) return null;
  const requestedBucket = typeof row.bucket === 'string' ? row.bucket : 'urgent';
  return {
    id: typeof row.id === 'string' ? row.id.slice(0, 180) : `${runId}:${index}`,
    bucket: BUCKETS.has(requestedBucket) ? requestedBucket as Finding['bucket'] : 'urgent',
    title,
    detail: typeof row.detail === 'string' ? row.detail.trim().slice(0, 300) : null,
    severity: typeof row.severity === 'string' ? row.severity.slice(0, 30) : 'medium',
    sourceId: typeof row.source_id === 'string' ? row.source_id.slice(0, 100) : null,
  };
}

function fallbackFinding(issue: PaperclipIssue, bucket: Finding['bucket']): Finding {
  return {
    id: `paperclip:${issue.paperclip_issue_id}:${bucket}`,
    bucket,
    title: issue.title.slice(0, 180),
    detail: issue.identifier ? `${issue.identifier} · Paperclip comparison` : 'Paperclip comparison',
    severity: issue.priority || 'medium',
    sourceId: issue.identifier,
  };
}

function RobotAvatar({ agent, large = false }: { agent: Agent; large?: boolean }) {
  const dark = agent.slug === 'stace' ? '#9a3412'
    : agent.slug === 'bruce' ? '#172554'
      : agent.slug === 'rodney' ? '#14532d'
        : agent.slug === 'derrick' ? '#134e4a' : '#713f12';
  const working = agent.status === 'running';
  return (
    <div className={`relative shrink-0 ${large ? 'h-24 w-24' : 'h-16 w-16'}`} aria-label={`${agent.name} robot`}>
      {working && <span className="absolute inset-1 rounded-full bg-blue-400/25 animate-ping" />}
      <svg viewBox="0 0 120 120" className="relative h-full w-full drop-shadow-md" role="img">
        <ellipse cx="60" cy="108" rx="35" ry="6" fill="#0f172a" opacity=".16" />
        {agent.accessory === 'hard_hat_hammer' && <path d="M25 29 Q29 7 60 7 Q91 7 95 29 Z" fill="#facc15" stroke={dark} strokeWidth="4" />}
        <line x1="60" y1="17" x2="60" y2="8" stroke={dark} strokeWidth="4" />
        <circle cx="60" cy="6" r="4" fill={working ? '#22c55e' : '#f59e0b'} />
        <rect x="25" y="18" width="70" height="50" rx="17" fill={agent.colour} stroke={dark} strokeWidth="4" />
        <rect x="34" y="29" width="52" height="27" rx="10" fill="#f8fafc" />
        <circle cx="49" cy="42" r="5" fill={dark} /><circle cx="72" cy="42" r="5" fill={dark} />
        <path d="M49 51 Q60 58 72 51" fill="none" stroke={dark} strokeWidth="3" strokeLinecap="round" />
        {agent.accessory === 'calendar_headset' && <path d="M24 34 Q13 43 24 55 M96 34 Q107 43 96 55 M101 54 L107 61" fill="none" stroke={dark} strokeWidth="4" strokeLinecap="round" />}
        <rect x="31" y="67" width="58" height="32" rx="12" fill={agent.colour} stroke={dark} strokeWidth="4" />
        <line x1="31" y1="76" x2="17" y2="87" stroke={dark} strokeWidth="7" strokeLinecap="round" />
        <line x1="89" y1="76" x2="103" y2="87" stroke={dark} strokeWidth="7" strokeLinecap="round" />
        <line x1="47" y1="98" x2="43" y2="108" stroke={dark} strokeWidth="8" strokeLinecap="round" />
        <line x1="73" y1="98" x2="77" y2="108" stroke={dark} strokeWidth="8" strokeLinecap="round" />
        {agent.accessory === 'clipboard' && <><rect x="48" y="72" width="25" height="23" rx="3" fill="#fff" /><path d="M53 80 H68 M53 86 H65" stroke={dark} strokeWidth="2" /></>}
        {agent.accessory === 'calendar_headset' && <><rect x="48" y="74" width="24" height="19" rx="3" fill="#fff7ed" /><path d="M48 80 H72" stroke={dark} strokeWidth="2" /><circle cx="55" cy="86" r="2" fill={agent.colour} /><circle cx="65" cy="86" r="2" fill={agent.colour} /></>}
        {agent.accessory === 'quote_sheet' && <><rect x="45" y="72" width="30" height="23" rx="3" fill="#f0fdf4" /><path d="M51 88 L57 82 L62 86 L69 77" fill="none" stroke={dark} strokeWidth="3" /></>}
        {agent.accessory === 'ledger_pound' && <><rect x="45" y="72" width="30" height="23" rx="3" fill="#f0fdfa" /><text x="60" y="90" textAnchor="middle" fontSize="18" fontWeight="800" fill={dark}>£</text></>}
        {agent.accessory === 'hard_hat_hammer' && <path d="M48 84 H72 M64 76 L72 84 L64 92" fill="none" stroke="#fef3c7" strokeWidth="4" strokeLinecap="round" />}
      </svg>
    </div>
  );
}

export default function VirtualOfficePage() {
  const [agents, setAgents] = useState<Agent[]>([]);
  const [runs, setRuns] = useState<AgentRun[]>([]);
  const [proposals, setProposals] = useState<Proposal[]>([]);
  const [connectors, setConnectors] = useState<Connector[]>([]);
  const [paperclipConnection, setPaperclipConnection] = useState<PaperclipConnection | null>(null);
  const [paperclipIssues, setPaperclipIssues] = useState<PaperclipIssue[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState('');
  const [selectedAgentId, setSelectedAgentId] = useState<string | null>(null);
  const [proposalToReview, setProposalToReview] = useState<Proposal | null>(null);

  const load = useCallback(async (quiet = false) => {
    if (!quiet) setLoading(true);
    const [agentsResult, runsResult, proposalsResult, connectorsResult, paperclipResult, paperclipIssuesResult] = await Promise.all([
      supabase.from('ai_agents').select('*').order('name'),
      supabase.from('ai_agent_runs').select('id,agent_id,status,summary,items,item_count,error,trigger_type,started_at,finished_at').order('started_at', { ascending: false }).limit(40),
      supabase.from('ai_action_proposals').select('id,agent_id,category,title,summary,risk_level,status,created_at').order('created_at', { ascending: false }).limit(40),
      supabase.from('integration_health').select('connector,display_name,provider,status,last_checked_at,last_success_at,last_error').order('display_name'),
      supabase.from('paperclip_connection_status').select('connected,last_seen_at,last_success_at,last_error').maybeSingle(),
      supabase.from('paperclip_issues').select('paperclip_issue_id,identifier,title,status,priority,updated_at').order('updated_at', { ascending: false }).limit(80),
    ]);
    const firstError = [agentsResult.error, runsResult.error, proposalsResult.error, connectorsResult.error].find(Boolean);
    if (firstError) {
      setError(firstError.message.includes('does not exist') ? 'The AI Workforce database upgrade still needs to be installed.' : firstError.message);
    } else {
      setError('');
      setAgents((agentsResult.data ?? []) as Agent[]);
      setRuns((runsResult.data ?? []) as AgentRun[]);
      setProposals((proposalsResult.data ?? []) as Proposal[]);
      setConnectors((connectorsResult.data ?? []) as Connector[]);
    }
    if (!paperclipResult.error) setPaperclipConnection(paperclipResult.data as PaperclipConnection | null);
    if (!paperclipIssuesResult.error) setPaperclipIssues((paperclipIssuesResult.data ?? []) as PaperclipIssue[]);
    setLoading(false);
  }, []);

  useEffect(() => {
    void load();
    const channel = supabase.channel('proline-ai-workforce')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'ai_agents' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'ai_agent_runs' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'ai_action_proposals' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'integration_health' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'paperclip_connection_status' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'paperclip_issues' }, () => void load(true))
      .subscribe();
    const timer = window.setInterval(() => void load(true), 30_000);
    return () => { window.clearInterval(timer); void supabase.removeChannel(channel); };
  }, [load]);

  useEffect(() => {
    if (!selectedAgentId && agents.length) setSelectedAgentId(agents.find((agent) => agent.pilot)?.id ?? agents[0].id);
  }, [agents, selectedAgentId]);

  const latestRuns = useMemo(() => {
    const byAgent = new Map<string, AgentRun>();
    for (const run of runs) if (!byAgent.has(run.agent_id)) byAgent.set(run.agent_id, run);
    return byAgent;
  }, [runs]);

  const findings = useMemo(() => {
    const result: Finding[] = [];
    for (const run of latestRuns.values()) {
      if (!Array.isArray(run.items)) continue;
      run.items.slice(0, 8).forEach((item, index) => {
        const finding = normaliseFinding(item, run.id, index);
        if (finding) result.push(finding);
      });
    }
    if (result.length) return result.slice(0, 24);
    const active = paperclipIssues.filter((issue) => ACTIVE_ISSUE_STATUSES.has(issue.status));
    const moneyPattern = /deposit|balance|payment|invoice|unpaid|cash/i;
    const money = active.filter((issue) => moneyPattern.test(issue.title)).slice(0, 4).map((issue) => fallbackFinding(issue, 'money'));
    const waiting = active.filter((issue) => issue.status === 'blocked').slice(0, 4).map((issue) => fallbackFinding(issue, 'waiting'));
    const used = new Set([...money, ...waiting].map((item) => item.sourceId));
    const urgent = active.filter((issue) => !used.has(issue.identifier) && ['urgent', 'high'].includes(issue.priority || '')).slice(0, 4).map((issue) => fallbackFinding(issue, 'urgent'));
    return [...urgent, ...waiting, ...money];
  }, [latestRuns, paperclipIssues]);

  const pendingProposals = proposals.filter((proposal) => proposal.status === 'pending');
  const selectedAgent = agents.find((agent) => agent.id === selectedAgentId) ?? null;
  const stace = agents.find((agent) => agent.slug === 'stace') ?? null;
  const grok = connectors.find((connector) => connector.connector === 'grok_bot');
  const grokConnected = grok?.status === 'connected';
  const paperclipFresh = Boolean(paperclipConnection?.last_seen_at && Date.now() - new Date(paperclipConnection.last_seen_at).getTime() < 90_000);
  const paperclipOnline = Boolean(paperclipConnection?.connected && paperclipFresh);
  const pilotDays = new Set(runs.filter((run) => run.agent_id === stace?.id && run.status === 'succeeded').map((run) => new Date(run.started_at).toLocaleDateString('en-CA', { timeZone: 'Europe/London' }))).size;

  async function runNow(agent: Agent) {
    setBusy(`run:${agent.id}`);
    const { data, error: invokeError } = await supabase.functions.invoke('ai-agent-control', { body: { action: 'run_agent', agent_id: agent.id } });
    if (invokeError || data?.error) setNotice(data?.message || 'Grok Bot is not connected yet. No billing change was made.');
    else { setNotice(`${agent.name} accepted the run request.`); void load(true); }
    setBusy('');
    window.setTimeout(() => setNotice(''), 6000);
  }

  async function reviewProposal(decision: 'approved' | 'rejected') {
    if (!proposalToReview) return;
    setBusy(`proposal:${proposalToReview.id}`);
    const { data, error: invokeError } = await supabase.functions.invoke('ai-agent-control', { body: { action: 'review_proposal', proposal_id: proposalToReview.id, decision } });
    if (invokeError || data?.error) setNotice('That decision could not be recorded. Refresh and try again.');
    else { setNotice(decision === 'approved' ? 'Approved for the next controlled step. Nothing was executed automatically.' : 'Proposal rejected.'); void load(true); }
    setBusy(''); setProposalToReview(null);
    window.setTimeout(() => setNotice(''), 6000);
  }

  if (loading && !agents.length) return <div className="h-full grid place-items-center bg-slate-50"><RefreshCw className="animate-spin text-orange-500" size={28} /></div>;

  return (
    <div className="h-full overflow-y-auto bg-slate-50 p-3 sm:p-5 lg:p-6">
      <div className="mx-auto max-w-[1500px] space-y-4">
        <section className="relative overflow-hidden rounded-3xl bg-slate-950 p-5 text-white shadow-xl sm:p-7">
          <div className="absolute -right-16 -top-16 h-64 w-64 rounded-full bg-orange-500/15" />
          <div className="relative flex flex-col gap-5 lg:flex-row lg:items-center">
            <div className="flex-1">
              <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-[.2em] text-orange-300"><Sparkles size={15} /> AI workforce pilot</div>
              <h2 className="mt-2 text-2xl font-black sm:text-3xl">ProLine Virtual Office</h2>
              <p className="mt-2 max-w-2xl text-sm text-slate-300">Stace is the only pilot. ProLine stays in control, consequential actions wait for approval, and Paperclip remains the fallback.</p>
            </div>
            <div className="grid grid-cols-3 gap-2"><Metric value={agents.length} label="Roles" /><Metric value={pilotDays} suffix="/5" label="Pilot days" /><Metric value={pendingProposals.length} label="Approvals" alert={pendingProposals.length > 0} /></div>
            <div className="min-w-56 rounded-2xl border border-white/10 bg-white/10 px-4 py-3"><div className="flex items-center gap-3"><span className={`h-3 w-3 rounded-full ${grokConnected ? 'bg-green-400 shadow-[0_0_15px_#4ade80]' : 'bg-amber-400'}`} /><div className="min-w-0 flex-1"><p className="text-sm font-bold">{grokConnected ? 'Grok connected' : 'Grok setup required'}</p><p className="truncate text-xs text-slate-400">No purchase made by ProLine</p></div><button onClick={() => void load()} title="Refresh" className="rounded-lg p-2 hover:bg-white/10"><RefreshCw size={16} /></button></div></div>
          </div>
        </section>

        {error && <Alert title="Virtual Office upgrade needed" text={error} />}
        {notice && <div className="rounded-2xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm font-semibold text-blue-800">{notice}</div>}

        {!grokConnected && <section className="rounded-3xl border border-amber-200 bg-amber-50 p-5 shadow-sm"><div className="flex flex-col gap-4 lg:flex-row lg:items-center"><div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-amber-500 text-white"><Cloud size={22} /></div><div className="flex-1"><p className="font-black text-amber-950">Stace is prepared, but Grok Bot has not been bought or connected</p><p className="mt-1 text-sm text-amber-800">Check entitlement first. If included, create Stace and connect the read-only ProLine MCP. Do not enable extra usage or API billing.</p></div><div className="flex flex-wrap gap-2"><a href="https://x.ai/pricing" target="_blank" rel="noreferrer" className="inline-flex items-center gap-2 rounded-xl border border-amber-300 bg-white px-4 py-2.5 text-sm font-bold text-amber-900"><ExternalLink size={15} /> Check plans</a><a href="https://qzvdzzvkocmulcfujyea.supabase.co/functions/v1/proline-mcp/health" target="_blank" rel="noreferrer" className="inline-flex items-center gap-2 rounded-xl bg-amber-900 px-4 py-2.5 text-sm font-bold text-white"><Plug size={15} /> MCP health</a></div></div></section>}

        <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <WorkBucket title="Needs your approval" icon={<ShieldCheck size={18} />} tone="violet" count={pendingProposals.length}>{pendingProposals.slice(0, 4).map((proposal) => <ProposalLine key={proposal.id} proposal={proposal} onOpen={() => setProposalToReview(proposal)} />)}</WorkBucket>
          <WorkBucket title="Urgent today" icon={<AlertCircle size={18} />} tone="red" count={findings.filter((item) => item.bucket === 'urgent').length}>{findings.filter((item) => item.bucket === 'urgent').slice(0, 4).map((item) => <FindingLine key={item.id} item={item} />)}</WorkBucket>
          <WorkBucket title="Waiting on someone" icon={<Activity size={18} />} tone="amber" count={findings.filter((item) => item.bucket === 'waiting').length}>{findings.filter((item) => item.bucket === 'waiting').slice(0, 4).map((item) => <FindingLine key={item.id} item={item} />)}</WorkBucket>
          <WorkBucket title="Money to chase" icon={<Wallet size={18} />} tone="green" count={findings.filter((item) => item.bucket === 'money').length}>{findings.filter((item) => item.bucket === 'money').slice(0, 4).map((item) => <FindingLine key={item.id} item={item} />)}</WorkBucket>
        </section>

        <section className="overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-sm">
          <div className="flex items-center gap-2 border-b border-slate-100 px-5 py-4"><Bot size={19} className="text-orange-500" /><h3 className="font-extrabold text-slate-800">Your AI team</h3><span className="ml-auto text-xs text-slate-400">Only Stace activates during the pilot</span></div>
          <div className="divide-y divide-slate-100">{agents.map((agent) => { const latest = latestRuns.get(agent.id); const selected = selectedAgentId === agent.id; return <button key={agent.id} onClick={() => setSelectedAgentId(agent.id)} className={`grid w-full items-center gap-3 px-4 py-4 text-left transition-colors sm:grid-cols-[72px_1.2fr_1.5fr_1fr_auto] ${selected ? 'bg-orange-50/70' : 'hover:bg-slate-50'}`}><RobotAvatar agent={agent} /><div className="min-w-0"><div className="flex flex-wrap items-center gap-2"><p className="font-black text-slate-900">{agent.name}</p>{agent.pilot && <span className="rounded-full bg-orange-100 px-2 py-0.5 text-[10px] font-black uppercase text-orange-700">Pilot</span>}</div><p className="truncate text-xs text-slate-500">{agent.title}</p></div><div className="min-w-0"><p className="text-[10px] font-bold uppercase tracking-wider text-slate-400">Current work</p><p className="mt-1 truncate text-sm font-semibold text-slate-700">{agent.current_work || latest?.summary || (agent.status === 'planned' ? 'Starts after Stace passes' : 'Waiting for Grok connection')}</p></div><div><p className="text-[10px] font-bold uppercase tracking-wider text-slate-400">Next run</p><p className="mt-1 text-xs font-semibold text-slate-600">{agent.next_run_at ? relativeTime(agent.next_run_at) : agent.schedule_label || 'Not scheduled'}</p><p className="mt-1 text-[11px] text-slate-400">Check-in {relativeTime(agent.last_checkin_at)}</p></div><span className={`justify-self-start rounded-full border px-2.5 py-1 text-[10px] font-black sm:justify-self-end ${statusStyle(agent.status)}`}>{titleCase(agent.status)}</span></button>; })}</div>
        </section>

        {selectedAgent && <section className="grid gap-4 lg:grid-cols-[1.1fr_1fr_1fr]">
          <div className="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm"><div className="flex items-center gap-4"><RobotAvatar agent={selectedAgent} large /><div><p className="text-xs font-bold uppercase tracking-wider text-slate-400">Selected bot</p><h3 className="text-xl font-black text-slate-900">{selectedAgent.name}</h3><p className="text-sm text-slate-500">{selectedAgent.title}</p></div></div><div className="mt-4 space-y-2"><InfoRow label="Provider" value={titleCase(selectedAgent.provider)} /><InfoRow label="Schedule" value={selectedAgent.schedule_label || 'Not enabled'} /><InfoRow label="Last success" value={relativeTime(selectedAgent.last_success_at)} /></div>{selectedAgent.pilot ? <button disabled={!grokConnected || busy === `run:${selectedAgent.id}`} onClick={() => void runNow(selectedAgent)} className="mt-5 flex w-full items-center justify-center gap-2 rounded-xl bg-orange-600 py-3 text-sm font-black text-white disabled:bg-slate-200 disabled:text-slate-400"><Play size={16} /> {grokConnected ? 'Run Stace now' : 'Connect Grok to run'}</button> : <div className="mt-5 rounded-xl bg-slate-50 p-3 text-xs font-semibold text-slate-500">Locked until the five-day Stace pilot passes.</div>}</div>
          <PilotGate days={pilotDays} connected={grokConnected} hasSafeRuns={runs.some((run) => run.agent_id === stace?.id && run.status === 'succeeded' && run.item_count <= 8)} />
          <div className="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm"><div className="flex items-center gap-2"><ShieldCheck size={19} className="text-green-600" /><h3 className="font-black text-slate-900">Safety boundary</h3></div><ul className="mt-4 space-y-2 text-sm text-slate-600"><SafeLine text="Read-only CRM during the pilot" /><SafeLine text="Maximum eight short findings" /><SafeLine text="Customer messages stay as drafts" /><SafeLine text="Money, purchases and schedules require approval" /><SafeLine text="No API billing enabled by ProLine" /></ul></div>
        </section>}

        <section className="grid gap-4 lg:grid-cols-2">
          <div className="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm"><div className="flex items-center gap-2"><Plug size={18} className="text-blue-600" /><h3 className="font-black text-slate-900">Connections</h3></div><div className="mt-4 divide-y divide-slate-100">{connectors.map((connector) => <div key={connector.connector} className="flex items-center gap-3 py-3"><span className={`h-2.5 w-2.5 rounded-full ${['connected', 'available'].includes(connector.status) ? 'bg-green-500' : connector.status === 'setup_required' ? 'bg-amber-500' : 'bg-red-500'}`} /><div className="min-w-0 flex-1"><p className="text-sm font-bold text-slate-800">{connector.display_name}</p><p className="truncate text-xs text-slate-400">{connector.last_error || `Last checked ${relativeTime(connector.last_checked_at)}`}</p></div><span className={`rounded-full border px-2 py-1 text-[10px] font-black ${statusStyle(connector.status)}`}>{titleCase(connector.status)}</span></div>)}</div></div>
          <div className="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm"><div className="flex items-center gap-2"><Cloud size={18} className="text-slate-600" /><h3 className="font-black text-slate-900">Paperclip comparison fallback</h3><span className={`ml-auto rounded-full border px-2 py-1 text-[10px] font-black ${statusStyle(paperclipOnline ? 'available' : 'degraded')}`}>{paperclipOnline ? 'Online' : 'Waiting'}</span></div><p className="mt-3 text-sm text-slate-500">Paperclip stays available during the Stace pilot. Its open tasks are used only as a comparison when no Grok check-in exists.</p><div className="mt-4 grid grid-cols-3 gap-2"><DeskStat label="Open tasks" value={String(paperclipIssues.filter((issue) => ACTIVE_ISSUE_STATUSES.has(issue.status)).length)} /><DeskStat label="Last sync" value={relativeTime(paperclipConnection?.last_seen_at)} /><DeskStat label="Role" value="Fallback" /></div></div>
        </section>

        <details className="rounded-3xl border border-slate-200 bg-white shadow-sm"><summary className="flex cursor-pointer list-none items-center gap-2 px-5 py-4 text-sm font-black text-slate-700"><ChevronDown size={17} /> Admin details and run history <span className="ml-auto text-xs font-medium text-slate-400">Hidden by default</span></summary><div className="border-t border-slate-100 px-5 py-4">{runs.length ? <div className="space-y-3">{runs.slice(0, 12).map((run) => { const agent = agents.find((item) => item.id === run.agent_id); return <div key={run.id} className="flex flex-col gap-1 rounded-xl bg-slate-50 p-3 sm:flex-row sm:items-center"><div className="min-w-0 flex-1"><p className="truncate text-sm font-bold text-slate-700">{agent?.name || 'Agent'} · {run.summary || titleCase(run.trigger_type)}</p><p className="text-xs text-slate-400">{relativeTime(run.started_at)} · {run.item_count} findings</p></div><span className={`self-start rounded-full border px-2 py-1 text-[10px] font-black ${statusStyle(run.status)}`}>{titleCase(run.status)}</span></div>; })}</div> : <p className="text-sm text-slate-400">No Grok pilot runs have been recorded yet.</p>}</div></details>
      </div>

      {proposalToReview && <div className="fixed inset-0 z-[100] grid place-items-center bg-slate-950/60 p-4" onMouseDown={(event) => { if (event.target === event.currentTarget) setProposalToReview(null); }}><div className="w-full max-w-lg rounded-3xl bg-white p-6 shadow-2xl"><div className="flex items-start gap-3"><div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-violet-100 text-violet-700"><ShieldCheck size={20} /></div><div className="flex-1"><p className="text-xs font-black uppercase tracking-wider text-violet-600">Approval required</p><h3 className="mt-1 text-xl font-black text-slate-900">{proposalToReview.title}</h3><p className="mt-2 text-sm text-slate-600">{proposalToReview.summary}</p><p className="mt-3 text-xs font-bold text-slate-400">{titleCase(proposalToReview.category)} · {titleCase(proposalToReview.risk_level)} risk</p></div><button onClick={() => setProposalToReview(null)} className="p-1 text-slate-400"><X size={20} /></button></div><div className="mt-6 rounded-xl bg-amber-50 p-3 text-xs font-semibold text-amber-800">Approval records your decision only. It does not send, purchase, delete, move money or change a live job automatically.</div><div className="mt-5 flex gap-3"><button disabled={Boolean(busy)} onClick={() => void reviewProposal('rejected')} className="flex-1 rounded-xl border border-slate-200 py-3 text-sm font-black text-slate-600">Reject</button><button disabled={Boolean(busy)} onClick={() => void reviewProposal('approved')} className="flex-1 rounded-xl bg-violet-700 py-3 text-sm font-black text-white">Approve next step</button></div></div></div>}
    </div>
  );
}

function Metric({ value, suffix = '', label, alert = false }: { value: number; suffix?: string; label: string; alert?: boolean }) {
  return <div className={`min-w-20 rounded-2xl border px-3 py-3 text-center ${alert ? 'border-violet-300/30 bg-violet-500/20' : 'border-white/10 bg-white/10'}`}><p className="text-xl font-black">{value}{suffix}</p><p className="text-[10px] uppercase tracking-wider text-slate-300">{label}</p></div>;
}

function Alert({ title, text }: { title: string; text: string }) {
  return <div className="flex items-start gap-3 rounded-2xl border border-red-200 bg-red-50 p-4 text-red-800"><AlertCircle size={20} className="mt-0.5 shrink-0" /><div><p className="font-bold">{title}</p><p className="mt-0.5 text-sm">{text}</p></div></div>;
}

const toneClasses = { violet: 'border-violet-200 bg-violet-50 text-violet-900', red: 'border-red-200 bg-red-50 text-red-900', amber: 'border-amber-200 bg-amber-50 text-amber-900', green: 'border-emerald-200 bg-emerald-50 text-emerald-900' };

function WorkBucket({ title, icon, tone, count, children }: { title: string; icon: React.ReactNode; tone: keyof typeof toneClasses; count: number; children: React.ReactNode }) {
  return <section className={`min-h-52 rounded-3xl border p-4 ${toneClasses[tone]}`}><div className="flex items-center gap-2"><span>{icon}</span><h3 className="font-black">{title}</h3><span className="ml-auto rounded-full bg-white/70 px-2 py-0.5 text-xs font-black">{count}</span></div><div className="mt-3 space-y-2">{count ? children : <div className="rounded-2xl border border-current/10 bg-white/60 px-3 py-5 text-center text-xs font-semibold opacity-60"><CheckCircle2 size={20} className="mx-auto mb-2" />Nothing waiting</div>}</div></section>;
}

function FindingLine({ item }: { item: Finding }) { return <div className="rounded-2xl border border-current/10 bg-white p-3"><p className="line-clamp-2 text-sm font-bold">{item.title}</p>{item.detail && <p className="mt-1 line-clamp-1 text-xs opacity-65">{item.detail}</p>}</div>; }
function ProposalLine({ proposal, onOpen }: { proposal: Proposal; onOpen: () => void }) { return <button onClick={onOpen} className="w-full rounded-2xl border border-violet-200 bg-white p-3 text-left hover:border-violet-400"><p className="line-clamp-2 text-sm font-bold text-slate-800">{proposal.title}</p><p className="mt-1 text-xs font-bold text-violet-600">Review {titleCase(proposal.risk_level)} risk</p></button>; }

function PilotGate({ days, connected, hasSafeRuns }: { days: number; connected: boolean; hasSafeRuns: boolean }) {
  const steps = [{ label: 'Grok entitlement confirmed', done: connected }, { label: 'Read-only MCP connected', done: connected }, { label: 'Eight-item limit proven', done: hasSafeRuns }, { label: 'Five business days completed', done: days >= 5 }, { label: 'Mac-off run confirmed by Will', done: false }];
  return <div className="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm"><div className="flex items-center gap-2"><Activity size={19} className="text-blue-600" /><h3 className="font-black text-slate-900">Pilot acceptance gate</h3><span className="ml-auto text-sm font-black text-blue-700">{Math.min(days, 5)}/5 days</span></div><div className="mt-4 space-y-2">{steps.map((step) => <div key={step.label} className="flex items-center gap-2 text-sm"><span className={`grid h-5 w-5 place-items-center rounded-full ${step.done ? 'bg-green-600 text-white' : 'bg-slate-100 text-slate-400'}`}>{step.done && <Check size={13} />}</span><span className={step.done ? 'font-semibold text-slate-700' : 'text-slate-500'}>{step.label}</span></div>)}</div></div>;
}

function SafeLine({ text }: { text: string }) { return <li className="flex items-start gap-2"><CheckCircle2 size={16} className="mt-0.5 shrink-0 text-green-600" /><span>{text}</span></li>; }
function InfoRow({ label, value }: { label: string; value: string }) { return <div className="flex items-center justify-between gap-3 border-b border-slate-100 pb-2 text-sm"><span className="text-slate-400">{label}</span><span className="text-right font-bold text-slate-700">{value}</span></div>; }
function DeskStat({ label, value }: { label: string; value: string }) { return <div className="rounded-xl bg-slate-50 px-3 py-2"><p className="text-[10px] font-bold uppercase text-slate-400">{label}</p><p className="mt-1 truncate text-xs font-black text-slate-700">{value}</p></div>; }

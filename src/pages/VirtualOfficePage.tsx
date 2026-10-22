import { useEffect, useMemo, useState } from 'react';
import { Building2, ExternalLink, Loader2, RefreshCw, WifiOff } from 'lucide-react';
import { usePaperclipStore } from '../store/usePaperclipStore';
import { useStore } from '../store/useStore';
import { canReachPaperclip, getPaperclipUrl } from '../lib/paperclip';
import AgentDesk from '../components/VirtualOffice/AgentDesk';
import AgentPanel from '../components/VirtualOffice/AgentPanel';
import Noticeboard from '../components/VirtualOffice/Noticeboard';
import { buildRooms } from '../components/VirtualOffice/officeUtils';

const POLL_MS = 8000;

export default function VirtualOfficePage() {
  const { setCurrentPage } = useStore();
  const { connection, error, companies, companyId, agents, liveRuns, activity, issues, lastUpdated, refresh, selectCompany } = usePaperclipStore();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const reachable = canReachPaperclip();

  useEffect(() => {
    if (!reachable) return;
    void refresh();
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') void refresh();
    }, POLL_MS);
    return () => window.clearInterval(timer);
  }, [reachable, refresh]);

  const runByAgent = useMemo(() => {
    const map = new Map<string, (typeof liveRuns)[number]>();
    for (const run of liveRuns) {
      const existing = map.get(run.agentId);
      if (!existing || run.status === 'running') map.set(run.agentId, run);
    }
    return map;
  }, [liveRuns]);

  const issuesByAgent = useMemo(() => {
    const map = new Map<string, typeof issues>();
    for (const issue of issues) {
      if (!issue.assigneeAgentId) continue;
      map.set(issue.assigneeAgentId, [...(map.get(issue.assigneeAgentId) ?? []), issue]);
    }
    return map;
  }, [issues]);

  const rooms = useMemo(() => buildRooms(agents), [agents]);
  const nameById = useMemo(() => new Map(agents.map(a => [a.id, a.name])), [agents]);
  const selected = agents.find(a => a.id === selectedId);
  const workingCount = agents.filter(a => runByAgent.get(a.id)?.status === 'running' || a.status === 'running').length;

  const currentIssueFor = (agentId: string) => {
    const run = runByAgent.get(agentId);
    const mine = issuesByAgent.get(agentId) ?? [];
    return mine.find(i => i.id === run?.issueId) ?? mine.find(i => i.status === 'in_progress');
  };

  if (!reachable) {
    return (
      <div className="h-full overflow-y-auto bg-gray-50 p-6 flex items-center justify-center">
        <div className="max-w-md text-center space-y-3">
          <Building2 size={40} className="mx-auto text-orange-500" />
          <h2 className="text-lg font-bold text-gray-800">Open the Virtual Office on your Mac</h2>
          <p className="text-sm text-gray-500">
            Your Paperclip agents run on your Mac, so for now the office opens in the ProLine Mac app.
            Viewing it from your phone is planned next.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="h-full overflow-y-auto bg-gray-50">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-gray-50/90 backdrop-blur border-b border-gray-200 px-4 sm:px-6 py-3 flex flex-wrap items-center gap-3">
        <div className="flex items-center gap-2">
          <Building2 size={20} className="text-orange-600" />
          <h1 className="font-bold text-gray-800">Virtual Office</h1>
        </div>
        <span className={`text-xs font-medium px-2.5 py-1 rounded-full flex items-center gap-1.5 ${
          connection === 'connected' ? 'bg-green-50 text-green-700'
            : connection === 'error' ? 'bg-red-50 text-red-700' : 'bg-gray-100 text-gray-500'
        }`}>
          <span className={`w-1.5 h-1.5 rounded-full ${connection === 'connected' ? 'bg-green-500' : connection === 'error' ? 'bg-red-500' : 'bg-gray-400'}`} />
          {connection === 'connected' ? `${workingCount} of ${agents.length} working` : connection === 'error' ? 'Paperclip not running' : 'Connecting…'}
        </span>
        {companies.length > 1 && (
          <select value={companyId} onChange={e => selectCompany(e.target.value)}
            className="text-sm border border-gray-200 rounded-lg px-2 py-1 bg-white focus:outline-none focus:ring-2 focus:ring-orange-400">
            {companies.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        )}
        <div className="ml-auto flex items-center gap-2">
          {lastUpdated && <span className="text-xs text-gray-400 hidden sm:inline">Updated {new Date(lastUpdated).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}</span>}
          <button onClick={() => void refresh()} className="p-2 rounded-lg hover:bg-gray-200 text-gray-500" title="Refresh">
            <RefreshCw size={16} />
          </button>
          <a href={getPaperclipUrl()} target="_blank" rel="noreferrer"
            className="flex items-center gap-1.5 text-sm font-medium px-3 py-1.5 rounded-lg bg-white border border-gray-200 hover:bg-gray-100 text-gray-700">
            <ExternalLink size={14} /> Open Paperclip
          </a>
        </div>
      </div>

      {connection === 'error' && (
        <div className="m-4 sm:m-6 p-5 rounded-2xl bg-white border border-red-100 shadow-sm flex gap-4">
          <WifiOff className="text-red-500 shrink-0" />
          <div className="text-sm text-gray-600 space-y-1">
            <p className="font-semibold text-gray-800">{error}</p>
            <p>Start Paperclip on this Mac. This page reconnects on its own once it's running.</p>
            <p>Running it somewhere else? Set the address in{' '}
              <button onClick={() => setCurrentPage('settings')} className="text-orange-600 font-medium hover:underline">Settings → Virtual Office</button>.
            </p>
          </div>
        </div>
      )}

      {connection === 'connecting' && agents.length === 0 && (
        <div className="flex items-center justify-center py-24 text-gray-400"><Loader2 className="animate-spin" /></div>
      )}

      {connection === 'connected' && agents.length === 0 && (
        <div className="m-6 p-8 rounded-2xl bg-white border border-gray-100 text-center text-sm text-gray-500">
          The office is empty. Hire your first agent in Paperclip and they'll appear here at their desk.
        </div>
      )}

      {agents.length > 0 && (
        <div className="p-4 sm:p-6 grid gap-6 lg:grid-cols-[1fr_320px]">
          <div className="space-y-6">
            {rooms.map(room => (
              <section key={room.name} className="rounded-3xl border-2 border-dashed border-gray-200 bg-white/60 p-4 sm:p-5">
                <h2 className="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-6">{room.name}</h2>
                <div className="grid gap-x-4 gap-y-7 grid-cols-1 sm:grid-cols-2 xl:grid-cols-3">
                  {room.agents.map(agent => (
                    <AgentDesk
                      key={agent.id}
                      agent={agent}
                      run={runByAgent.get(agent.id)}
                      currentIssue={currentIssueFor(agent.id)}
                      selected={agent.id === selectedId}
                      onSelect={() => setSelectedId(agent.id)}
                    />
                  ))}
                </div>
              </section>
            ))}
          </div>
          <Noticeboard agents={agents} issues={issues} activity={activity} />
        </div>
      )}

      {selected && (
        <AgentPanel
          agent={selected}
          run={runByAgent.get(selected.id)}
          issues={issuesByAgent.get(selected.id) ?? []}
          activity={activity.filter(a => a.agentId === selected.id || a.actorId === selected.id || a.entityId === selected.id)}
          nameById={nameById}
          onClose={() => setSelectedId(null)}
        />
      )}
    </div>
  );
}

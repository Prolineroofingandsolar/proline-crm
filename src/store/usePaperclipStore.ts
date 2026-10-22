import { create } from 'zustand';
import {
  listCompanies, listAgents, listLiveRuns, listActivity, listIssues,
  pauseAgent, resumeAgent, wakeAgent, createIssue, commentOnIssue,
  getSavedCompanyId, saveCompanyId,
  type PaperclipCompany, type PaperclipAgent, type PaperclipRun, type PaperclipActivity, type PaperclipIssue,
} from '../lib/paperclip';

type Connection = 'idle' | 'connecting' | 'connected' | 'error';

interface PaperclipState {
  connection: Connection;
  error: string | null;
  companies: PaperclipCompany[];
  companyId: string;
  agents: PaperclipAgent[];
  liveRuns: PaperclipRun[];
  activity: PaperclipActivity[];
  issues: PaperclipIssue[];
  lastUpdated: number | null;
  busyAgentIds: string[];

  refresh: () => Promise<void>;
  selectCompany: (id: string) => void;
  pause: (agentId: string) => Promise<void>;
  resume: (agentId: string) => Promise<void>;
  wake: (agentId: string) => Promise<void>;
  assignTask: (agentId: string, title: string, description: string) => Promise<void>;
  message: (issueId: string, body: string) => Promise<void>;
}

export const usePaperclipStore = create<PaperclipState>((set, get) => {
  // Run a control action with the agent marked busy, then refresh so the desk updates.
  async function control(agentId: string, action: () => Promise<unknown>, optimistic?: Partial<PaperclipAgent>) {
    set(s => ({
      busyAgentIds: [...s.busyAgentIds, agentId],
      agents: optimistic ? s.agents.map(a => a.id === agentId ? { ...a, ...optimistic } : a) : s.agents,
    }));
    try {
      await action();
    } finally {
      set(s => ({ busyAgentIds: s.busyAgentIds.filter(id => id !== agentId) }));
      void get().refresh();
    }
  }

  return {
    connection: 'idle',
    error: null,
    companies: [],
    companyId: getSavedCompanyId(),
    agents: [],
    liveRuns: [],
    activity: [],
    issues: [],
    lastUpdated: null,
    busyAgentIds: [],

    refresh: async () => {
      if (get().connection === 'idle') set({ connection: 'connecting' });
      try {
        const companies = await listCompanies();
        let companyId = get().companyId;
        if (!companies.some(c => c.id === companyId)) companyId = companies[0]?.id ?? '';
        if (!companyId) {
          set({ connection: 'connected', error: null, companies, companyId, agents: [], liveRuns: [], activity: [], issues: [], lastUpdated: Date.now() });
          return;
        }
        const [agents, liveRuns, activity, issues] = await Promise.all([
          listAgents(companyId),
          listLiveRuns(companyId),
          listActivity(companyId),
          listIssues(companyId),
        ]);
        set({ connection: 'connected', error: null, companies, companyId, agents, liveRuns, activity, issues, lastUpdated: Date.now() });
      } catch (err) {
        set({ connection: 'error', error: err instanceof Error ? err.message : 'Could not reach Paperclip' });
      }
    },

    selectCompany: (id) => {
      saveCompanyId(id);
      set({ companyId: id, agents: [], liveRuns: [], activity: [], issues: [] });
      void get().refresh();
    },

    pause: (agentId) => control(agentId, () => pauseAgent(agentId), { status: 'paused' }),
    resume: (agentId) => control(agentId, () => resumeAgent(agentId), { status: 'idle' }),
    wake: (agentId) => control(agentId, () => wakeAgent(agentId)),

    assignTask: (agentId, title, description) =>
      control(agentId, () => createIssue(get().companyId, { title, description: description || undefined, assigneeAgentId: agentId })),

    message: async (issueId, body) => {
      await commentOnIssue(issueId, body);
      void get().refresh();
    },
  };
});

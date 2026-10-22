import { useState } from 'react';
import { X, Pause, Play, Zap, ClipboardPlus, Send, Loader2 } from 'lucide-react';
import type { PaperclipActivity, PaperclipAgent, PaperclipIssue, PaperclipRun } from '../../lib/paperclip';
import { useStore } from '../../store/useStore';
import { usePaperclipStore } from '../../store/usePaperclipStore';
import NewTaskModal from './NewTaskModal';
import { DESK_STATE_STYLE, avatarColour, deskState, describeActivity, formatCents, initials, timeAgo } from './officeUtils';

interface Props {
  agent: PaperclipAgent;
  run?: PaperclipRun;
  issues: PaperclipIssue[];
  activity: PaperclipActivity[];
  nameById: Map<string, string>;
  onClose: () => void;
}

const ISSUE_STATUS_STYLE: Record<string, string> = {
  in_progress: 'bg-green-50 text-green-700',
  todo: 'bg-orange-50 text-orange-700',
  in_review: 'bg-sky-50 text-sky-700',
  blocked: 'bg-red-50 text-red-700',
  backlog: 'bg-gray-100 text-gray-600',
};

export default function AgentPanel({ agent, run, issues, activity, nameById, onClose }: Props) {
  const { showToast } = useStore();
  const { pause, resume, wake, assignTask, message, busyAgentIds } = usePaperclipStore();
  const [showTask, setShowTask] = useState(false);
  const [note, setNote] = useState('');
  const [sending, setSending] = useState(false);

  const state = deskState(agent, run);
  const busy = busyAgentIds.includes(agent.id);
  const currentIssue = issues.find(i => i.id === run?.issueId) ?? issues.find(i => i.status === 'in_progress') ?? issues[0];

  async function act(label: string, fn: () => Promise<void>) {
    try {
      await fn();
      showToast(label, 'success');
    } catch (err) {
      showToast(err instanceof Error ? err.message : 'Paperclip rejected that', 'error');
    }
  }

  async function sendNote() {
    if (!currentIssue || !note.trim()) return;
    setSending(true);
    try {
      await message(currentIssue.id, note.trim());
      setNote('');
      showToast(`Message sent to ${agent.name}`, 'success');
    } catch (err) {
      showToast(err instanceof Error ? err.message : 'Message failed', 'error');
    } finally {
      setSending(false);
    }
  }

  return (
    <>
      <div className="fixed inset-0 z-40 bg-black/30" onClick={onClose} />
      <aside className="fixed top-0 right-0 bottom-0 z-50 w-full sm:w-[420px] bg-white shadow-2xl flex flex-col pt-safe">
        <div className="flex items-start gap-3 px-5 py-4 border-b border-gray-100">
          <div className={`w-12 h-12 rounded-full ${avatarColour(agent.id)} text-white font-bold flex items-center justify-center shrink-0`}>
            {initials(agent.name)}
          </div>
          <div className="min-w-0 flex-1">
            <h2 className="font-bold text-gray-800 text-lg truncate">{agent.name}</h2>
            <p className="text-sm text-gray-500 truncate">{agent.title || agent.role}</p>
            <div className="flex items-center gap-1.5 mt-1 text-xs text-gray-500">
              <span className={`w-2 h-2 rounded-full ${DESK_STATE_STYLE[state].dot}`} />
              {DESK_STATE_STYLE[state].label} · last check-in {timeAgo(agent.lastHeartbeatAt)}
            </div>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-500"><X size={18} /></button>
        </div>

        <div className="flex-1 overflow-y-auto p-5 space-y-6">
          {/* Controls */}
          <div className="grid grid-cols-3 gap-2">
            {state === 'paused' ? (
              <button disabled={busy} onClick={() => act(`${agent.name} is back at work`, () => resume(agent.id))}
                className="flex flex-col items-center gap-1 py-3 rounded-xl bg-green-50 text-green-700 hover:bg-green-100 text-xs font-semibold disabled:opacity-50">
                <Play size={18} /> Resume
              </button>
            ) : (
              <button disabled={busy} onClick={() => act(`${agent.name} paused`, () => pause(agent.id))}
                className="flex flex-col items-center gap-1 py-3 rounded-xl bg-gray-50 text-gray-700 hover:bg-gray-100 text-xs font-semibold disabled:opacity-50">
                <Pause size={18} /> Pause
              </button>
            )}
            <button disabled={busy || state === 'paused'} onClick={() => act(`${agent.name} woken up`, () => wake(agent.id))}
              className="flex flex-col items-center gap-1 py-3 rounded-xl bg-orange-50 text-orange-700 hover:bg-orange-100 text-xs font-semibold disabled:opacity-50">
              {busy ? <Loader2 size={18} className="animate-spin" /> : <Zap size={18} />} Run now
            </button>
            <button disabled={busy} onClick={() => setShowTask(true)}
              className="flex flex-col items-center gap-1 py-3 rounded-xl bg-sky-50 text-sky-700 hover:bg-sky-100 text-xs font-semibold disabled:opacity-50">
              <ClipboardPlus size={18} /> Give task
            </button>
          </div>

          {/* Doing now */}
          <section>
            <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-2">Doing now</h3>
            {currentIssue ? (
              <div className="rounded-xl border border-gray-100 p-3">
                <div className="text-xs text-gray-400">{currentIssue.identifier}</div>
                <div className="font-medium text-gray-800">{currentIssue.title}</div>
                <div className="mt-3 flex gap-2">
                  <input value={note} onChange={e => setNote(e.target.value)} onKeyDown={e => { if (e.key === 'Enter') void sendNote(); }}
                    className="flex-1 border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
                    placeholder={`Message ${agent.name} about this…`} />
                  <button onClick={sendNote} disabled={sending || !note.trim()}
                    className="px-3 rounded-lg bg-orange-600 hover:bg-orange-700 text-white disabled:opacity-50">
                    {sending ? <Loader2 size={15} className="animate-spin" /> : <Send size={15} />}
                  </button>
                </div>
              </div>
            ) : (
              <p className="text-sm text-gray-500">Nothing assigned. Give them a task to get started.</p>
            )}
          </section>

          {/* Budget */}
          {agent.budgetMonthlyCents > 0 && (
            <section>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-2">Budget this month</h3>
              <div className="text-sm text-gray-700">{formatCents(agent.spentMonthlyCents)} of {formatCents(agent.budgetMonthlyCents)}</div>
            </section>
          )}

          {/* Assigned work */}
          <section>
            <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-2">Their to-do list ({issues.length})</h3>
            <ul className="space-y-1.5">
              {issues.map(issue => (
                <li key={issue.id} className="flex items-center gap-2 text-sm">
                  <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full shrink-0 ${ISSUE_STATUS_STYLE[issue.status] ?? 'bg-gray-100 text-gray-600'}`}>
                    {issue.status.replace('_', ' ')}
                  </span>
                  <span className="truncate text-gray-700">{issue.title}</span>
                </li>
              ))}
              {issues.length === 0 && <li className="text-sm text-gray-500">No open tasks.</li>}
            </ul>
          </section>

          {/* Activity */}
          <section>
            <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-2">Recent activity</h3>
            <ul className="space-y-2">
              {activity.slice(0, 20).map(entry => (
                <li key={entry.id} className="text-sm text-gray-600 flex gap-2">
                  <span className="text-xs text-gray-400 w-14 shrink-0 pt-0.5">{timeAgo(entry.createdAt)}</span>
                  <span>{describeActivity(entry, nameById)}</span>
                </li>
              ))}
              {activity.length === 0 && <li className="text-sm text-gray-500">No activity yet.</li>}
            </ul>
          </section>
        </div>
      </aside>

      {showTask && (
        <NewTaskModal
          agent={agent}
          onClose={() => setShowTask(false)}
          onSubmit={async (title, description) => {
            await assignTask(agent.id, title, description);
            showToast(`Task given to ${agent.name}`, 'success');
          }}
        />
      )}
    </>
  );
}

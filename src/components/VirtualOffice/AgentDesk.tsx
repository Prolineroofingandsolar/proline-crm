import { Monitor } from 'lucide-react';
import type { PaperclipAgent, PaperclipIssue, PaperclipRun } from '../../lib/paperclip';
import { DESK_STATE_STYLE, avatarColour, deskState, initials, timeAgo } from './officeUtils';

interface Props {
  agent: PaperclipAgent;
  run?: PaperclipRun;
  currentIssue?: PaperclipIssue;
  selected: boolean;
  onSelect: () => void;
}

export default function AgentDesk({ agent, run, currentIssue, selected, onSelect }: Props) {
  const state = deskState(agent, run);
  const style = DESK_STATE_STYLE[state];
  const budget = agent.budgetMonthlyCents;
  const spentPct = budget > 0 ? Math.min(100, Math.round((agent.spentMonthlyCents / budget) * 100)) : 0;
  const bubble = currentIssue?.title
    ?? (state === 'working' ? 'Working on something…' : state === 'paused' ? 'On a break' : state === 'error' ? 'Needs help' : 'Waiting for work');

  return (
    <button
      onClick={onSelect}
      className={`relative text-left bg-white rounded-2xl border p-4 pt-10 transition-all hover:shadow-md ${
        selected ? 'border-orange-400 shadow-md ring-2 ring-orange-200' : 'border-gray-100 shadow-sm'
      }`}
    >
      {/* Speech bubble */}
      <div className={`absolute -top-3 left-3 right-3 text-xs px-3 py-1.5 rounded-xl shadow-sm truncate ${
        state === 'working' ? 'bg-green-50 text-green-800 border border-green-200'
          : state === 'error' ? 'bg-red-50 text-red-700 border border-red-200'
          : 'bg-gray-50 text-gray-500 border border-gray-200'
      }`}>
        {bubble}
      </div>

      <div className="flex items-center gap-3">
        <div className="relative shrink-0">
          <div className={`w-12 h-12 rounded-full ${avatarColour(agent.id)} text-white font-bold flex items-center justify-center ring-4 ${style.ring} ${state === 'working' ? 'animate-pulse' : ''}`}>
            {initials(agent.name)}
          </div>
          <span className={`absolute -bottom-0.5 -right-0.5 w-3.5 h-3.5 rounded-full border-2 border-white ${style.dot}`} />
        </div>
        <div className="min-w-0">
          <div className="font-semibold text-gray-800 truncate">{agent.name}</div>
          <div className="text-xs text-gray-500 truncate">{agent.title || agent.role}</div>
        </div>
      </div>

      {/* Desk + monitor */}
      <div className="mt-3 flex items-center gap-2 text-xs text-gray-400">
        <Monitor size={14} className={state === 'working' ? 'text-green-500' : ''} />
        <span>{style.label}</span>
        {state === 'working' && (
          <span className="flex gap-0.5" aria-hidden>
            <span className="w-1 h-1 rounded-full bg-green-500 animate-bounce [animation-delay:-0.3s]" />
            <span className="w-1 h-1 rounded-full bg-green-500 animate-bounce [animation-delay:-0.15s]" />
            <span className="w-1 h-1 rounded-full bg-green-500 animate-bounce" />
          </span>
        )}
        <span className="ml-auto">{timeAgo(agent.lastHeartbeatAt)}</span>
      </div>

      {budget > 0 && (
        <div className="mt-2 h-1.5 rounded-full bg-gray-100 overflow-hidden" title={`${spentPct}% of monthly budget used`}>
          <div className={`h-full ${spentPct >= 90 ? 'bg-red-500' : spentPct >= 70 ? 'bg-amber-400' : 'bg-orange-500'}`} style={{ width: `${spentPct}%` }} />
        </div>
      )}
    </button>
  );
}

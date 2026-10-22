import type { PaperclipActivity, PaperclipAgent, PaperclipIssue } from '../../lib/paperclip';
import { describeActivity, formatCents, timeAgo } from './officeUtils';

interface Props {
  agents: PaperclipAgent[];
  issues: PaperclipIssue[];
  activity: PaperclipActivity[];
}

const COUNTS: { status: PaperclipIssue['status']; label: string; colour: string }[] = [
  { status: 'in_progress', label: 'In progress', colour: 'text-green-600' },
  { status: 'todo',        label: 'To do',       colour: 'text-orange-600' },
  { status: 'in_review',   label: 'In review',   colour: 'text-sky-600' },
  { status: 'blocked',     label: 'Blocked',     colour: 'text-red-600' },
];

export default function Noticeboard({ agents, issues, activity }: Props) {
  const nameById = new Map(agents.map(a => [a.id, a.name]));
  const spent = agents.reduce((sum, a) => sum + (a.spentMonthlyCents || 0), 0);
  const budget = agents.reduce((sum, a) => sum + (a.budgetMonthlyCents || 0), 0);

  return (
    <div className="space-y-4">
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-3">Work board</h3>
        <div className="grid grid-cols-2 gap-3">
          {COUNTS.map(({ status, label, colour }) => (
            <div key={status}>
              <div className={`text-2xl font-bold ${colour}`}>{issues.filter(i => i.status === status).length}</div>
              <div className="text-xs text-gray-500">{label}</div>
            </div>
          ))}
        </div>
        <div className="mt-3 pt-3 border-t border-gray-100 text-sm text-gray-600">
          Spend this month: <span className="font-semibold text-gray-800">{formatCents(spent)}</span>
          {budget > 0 && <span className="text-gray-400"> of {formatCents(budget)}</span>}
        </div>
      </div>

      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-3">Office chatter</h3>
        <ul className="space-y-2.5 max-h-[60vh] overflow-y-auto">
          {activity.slice(0, 40).map(entry => (
            <li key={entry.id} className="text-sm text-gray-600 flex gap-2">
              <span className="text-xs text-gray-400 w-14 shrink-0 pt-0.5">{timeAgo(entry.createdAt)}</span>
              <span>{describeActivity(entry, nameById)}</span>
            </li>
          ))}
          {activity.length === 0 && <li className="text-sm text-gray-500">Quiet in here. Nothing has happened yet.</li>}
        </ul>
      </div>
    </div>
  );
}

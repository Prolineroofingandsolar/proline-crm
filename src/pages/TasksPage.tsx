import { useState } from 'react';
import { CheckCircle2, Circle, ChevronRight, Plus, Trash2, Flag, Calendar, Tag, X, ChevronDown, ChevronUp } from 'lucide-react';
import { useStore } from '../store/useStore';
import type { GeneralTask } from '../store/useStore';
import { formatDate, formatDateShort, jobTypeColor } from '../utils/helpers';
import LeadDetailPanel from '../components/LeadDetail/LeadDetailPanel';

const PRIORITIES: { value: GeneralTask['priority']; label: string; color: string; dot: string }[] = [
  { value: 'high',   label: 'High',   color: 'text-red-600 bg-red-50 border-red-200',    dot: 'bg-red-500' },
  { value: 'medium', label: 'Medium', color: 'text-amber-600 bg-amber-50 border-amber-200', dot: 'bg-amber-400' },
  { value: 'low',    label: 'Low',    color: 'text-gray-500 bg-gray-50 border-gray-200',  dot: 'bg-gray-400' },
];

const CATEGORIES = ['Admin', 'Finance', 'Vehicle', 'Marketing', 'Health & Safety', 'Staff', 'Supplies', 'Other'];

type View = 'all' | 'todo' | 'done';

function PriorityBadge({ priority }: { priority: GeneralTask['priority'] }) {
  const p = PRIORITIES.find(x => x.value === priority)!;
  return (
    <span className={`inline-flex items-center gap-1 text-xs font-medium px-1.5 py-0.5 rounded-full border ${p.color}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${p.dot}`} />
      {p.label}
    </span>
  );
}

// ── Add General Task form ────────────────────────────────────────────────────
function AddGeneralTaskForm({ onClose }: { onClose: () => void }) {
  const { addGeneralTask } = useStore();
  const [title, setTitle]       = useState('');
  const [priority, setPriority] = useState<GeneralTask['priority']>('medium');
  const [category, setCategory] = useState('Admin');
  const [dueDate, setDueDate]   = useState('');
  const [notes, setNotes]       = useState('');

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    addGeneralTask({ title: title.trim(), priority, category, dueDate: dueDate || undefined, notes: notes || undefined });
    onClose();
  };

  return (
    <form onSubmit={submit} className="bg-orange-50 border border-orange-200 rounded-2xl p-4 space-y-3">
      <div className="flex items-center justify-between mb-1">
        <h4 className="font-semibold text-gray-800 text-sm">New General Task</h4>
        <button type="button" onClick={onClose} className="text-gray-400 hover:text-gray-600"><X size={15} /></button>
      </div>

      <input
        required autoFocus
        value={title} onChange={e => setTitle(e.target.value)}
        placeholder="What needs doing? e.g. MOT reminder, order materials…"
        className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
      />

      <div className="grid grid-cols-2 gap-2">
        <div>
          <label className="block text-xs font-semibold text-gray-500 mb-1">Priority</label>
          <select value={priority} onChange={e => setPriority(e.target.value as GeneralTask['priority'])}
            className="w-full border border-gray-200 rounded-lg px-2.5 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400">
            {PRIORITIES.map(p => <option key={p.value} value={p.value}>{p.label}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-xs font-semibold text-gray-500 mb-1">Category</label>
          <select value={category} onChange={e => setCategory(e.target.value)}
            className="w-full border border-gray-200 rounded-lg px-2.5 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400">
            {CATEGORIES.map(c => <option key={c}>{c}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-xs font-semibold text-gray-500 mb-1">Due date</label>
          <input type="date" value={dueDate} onChange={e => setDueDate(e.target.value)}
            className="w-full border border-gray-200 rounded-lg px-2.5 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
        </div>
        <div>
          <label className="block text-xs font-semibold text-gray-500 mb-1">Notes</label>
          <input value={notes} onChange={e => setNotes(e.target.value)} placeholder="Optional…"
            className="w-full border border-gray-200 rounded-lg px-2.5 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
        </div>
      </div>

      <div className="flex gap-2 pt-1">
        <button type="button" onClick={onClose}
          className="flex-1 border border-gray-200 bg-white text-gray-600 hover:bg-gray-50 py-2 rounded-xl text-sm font-medium">
          Cancel
        </button>
        <button type="submit"
          className="flex-1 bg-orange-600 hover:bg-orange-700 text-white py-2 rounded-xl text-sm font-bold">
          Add Task
        </button>
      </div>
    </form>
  );
}

// ── General Tasks section ────────────────────────────────────────────────────
function GeneralTasksSection({ view }: { view: View }) {
  const { generalTasks, toggleGeneralTask, deleteGeneralTask } = useStore();
  const [adding, setAdding] = useState(false);

  const filtered = generalTasks.filter(t =>
    view === 'all' ? true : view === 'todo' ? !t.completed : t.completed
  );

  const pending = generalTasks.filter(t => !t.completed).length;

  const isOverdue = (t: GeneralTask) =>
    !t.completed && t.dueDate && new Date(t.dueDate) < new Date();

  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
      {/* Section header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-gray-100 bg-gray-50">
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-lg bg-orange-100 flex items-center justify-center">
            <Flag size={14} className="text-orange-600" />
          </div>
          <div>
            <p className="font-bold text-gray-800 text-sm">General Tasks</p>
            <p className="text-xs text-gray-400">Reminders, admin, anything not tied to a job</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {pending > 0 && (
            <span className="bg-orange-100 text-orange-700 text-xs font-bold px-2 py-0.5 rounded-full">{pending} pending</span>
          )}
          <button
            onClick={() => setAdding(a => !a)}
            className="flex items-center gap-1 bg-orange-600 hover:bg-orange-700 text-white text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors"
          >
            <Plus size={13} /> Add Task
          </button>
        </div>
      </div>

      <div className="p-4 space-y-3">
        {adding && <AddGeneralTaskForm onClose={() => setAdding(false)} />}

        {filtered.length === 0 && !adding && (
          <div className="text-center py-6">
            <Flag size={28} className="mx-auto text-gray-200 mb-2" />
            <p className="text-sm text-gray-400">
              {view === 'done' ? 'No completed general tasks' : 'No pending general tasks'}
            </p>
            {view !== 'done' && (
              <button onClick={() => setAdding(true)} className="mt-2 text-xs text-orange-500 hover:text-orange-700 font-medium">
                + Add your first task
              </button>
            )}
          </div>
        )}

        {filtered.map(task => (
          <div key={task.id}
            className={`flex items-start gap-3 p-3 rounded-xl border transition-colors group ${
              task.completed
                ? 'bg-gray-50 border-gray-100 opacity-60'
                : isOverdue(task)
                ? 'bg-red-50 border-red-200'
                : 'bg-white border-gray-100 hover:border-orange-200'
            }`}
          >
            <button onClick={() => toggleGeneralTask(task.id)} className="mt-0.5 shrink-0">
              {task.completed
                ? <CheckCircle2 size={18} className="text-green-500" />
                : <Circle size={18} className="text-gray-300 hover:text-orange-500" />}
            </button>

            <div className="flex-1 min-w-0">
              <p className={`text-sm font-medium ${task.completed ? 'line-through text-gray-400' : isOverdue(task) ? 'text-red-800' : 'text-gray-800'}`}>
                {task.title}
              </p>
              <div className="flex flex-wrap items-center gap-1.5 mt-1">
                <PriorityBadge priority={task.priority} />
                <span className="inline-flex items-center gap-1 text-xs text-gray-400 bg-gray-50 border border-gray-100 px-1.5 py-0.5 rounded-full">
                  <Tag size={10} /> {task.category}
                </span>
                {task.dueDate && (
                  <span className={`inline-flex items-center gap-1 text-xs px-1.5 py-0.5 rounded-full border ${
                    isOverdue(task) ? 'text-red-600 bg-red-50 border-red-200 font-semibold' : 'text-gray-400 bg-gray-50 border-gray-100'
                  }`}>
                    <Calendar size={10} />
                    {isOverdue(task) ? 'Overdue · ' : ''}{formatDateShort(task.dueDate)}
                  </span>
                )}
                {task.completedDate && (
                  <span className="text-xs text-gray-300">Done {formatDate(task.completedDate)}</span>
                )}
              </div>
              {task.notes && <p className="text-xs text-gray-400 mt-1 italic">{task.notes}</p>}
            </div>

            <button onClick={() => deleteGeneralTask(task.id)}
              className="opacity-0 group-hover:opacity-100 shrink-0 text-gray-300 hover:text-red-500 transition-all mt-0.5">
              <Trash2 size={14} />
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Job Tasks section ────────────────────────────────────────────────────────
function JobTasksSection({ view }: { view: View }) {
  const { leads, toggleTask, setSelectedId } = useStore();
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({});

  const activeLeads = leads.filter(l =>
    ['Won', 'In Progress', 'Completed'].includes(l.stage) && l.tasks.length > 0
  );

  const leadsWithMatchingTasks = activeLeads.map(lead => {
    const tasks = lead.tasks.filter(t =>
      view === 'all' ? true : view === 'todo' ? !t.completed : t.completed
    );
    return { lead, tasks };
  }).filter(({ tasks }) => tasks.length > 0);

  const toggle = (id: string) => setCollapsed(c => ({ ...c, [id]: !c[id] }));

  if (leadsWithMatchingTasks.length === 0) {
    return (
      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-8 text-center">
        <CheckCircle2 size={36} className="mx-auto text-gray-200 mb-2" />
        <p className="text-sm text-gray-400">
          {view === 'done' ? 'No completed job tasks' : 'All job tasks are done!'}
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {leadsWithMatchingTasks.map(({ lead, tasks }) => {
        const done  = lead.tasks.filter(t => t.completed).length;
        const total = lead.tasks.length;
        const pct   = total ? Math.round((done / total) * 100) : 0;
        const isOpen = !collapsed[lead.id];

        return (
          <div key={lead.id} className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
            {/* Job header */}
            <div
              className="flex items-center gap-3 px-4 py-3 border-b border-gray-100 cursor-pointer hover:bg-gray-50 transition-colors"
              onClick={() => toggle(lead.id)}
            >
              <div className="w-8 h-8 rounded-lg bg-orange-100 flex items-center justify-center text-orange-700 font-bold text-sm shrink-0">
                {lead.name[0]}
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <p className="font-bold text-gray-800 text-sm">{lead.name}</p>
                  <span className={`text-xs font-medium px-1.5 py-0.5 rounded-md ${jobTypeColor(lead.jobType)}`}>{lead.jobType}</span>
                  <span className="text-xs text-gray-400 hidden sm:inline">{lead.jobRef}</span>
                </div>
                {/* Progress bar */}
                <div className="flex items-center gap-2 mt-1">
                  <div className="w-24 bg-gray-100 rounded-full h-1.5">
                    <div className="h-1.5 rounded-full bg-orange-500 transition-all" style={{ width: `${pct}%` }} />
                  </div>
                  <span className="text-xs text-gray-400">{done}/{total} done</span>
                </div>
              </div>
              <div className="flex items-center gap-2 shrink-0">
                <button
                  onClick={e => { e.stopPropagation(); setSelectedId(lead.id); }}
                  className="text-xs text-orange-500 hover:text-orange-700 font-medium flex items-center gap-0.5 px-2 py-1 rounded-lg hover:bg-orange-50"
                >
                  Open <ChevronRight size={12} />
                </button>
                {isOpen ? <ChevronUp size={15} className="text-gray-400" /> : <ChevronDown size={15} className="text-gray-400" />}
              </div>
            </div>

            {/* Tasks */}
            {isOpen && (
              <div className="divide-y divide-gray-50">
                {tasks.map(task => (
                  <div key={task.id}
                    className={`flex items-center gap-3 px-4 py-2.5 hover:bg-gray-50 group transition-colors ${task.completed ? 'opacity-60' : ''}`}
                  >
                    <button onClick={() => toggleTask(lead.id, task.id)} className="shrink-0">
                      {task.completed
                        ? <CheckCircle2 size={17} className="text-green-500" />
                        : <Circle size={17} className="text-gray-300 hover:text-orange-500" />}
                    </button>
                    <span className={`flex-1 text-sm ${task.completed ? 'line-through text-gray-400' : 'text-gray-700'}`}>
                      {task.title}
                    </span>
                    {task.completedDate && (
                      <span className="text-xs text-gray-300 shrink-0">{formatDateShort(task.completedDate)}</span>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ── Page ─────────────────────────────────────────────────────────────────────
export default function TasksPage() {
  const { leads, generalTasks, selectedId } = useStore();
  const [view, setView] = useState<View>('todo');

  const pendingGeneral = generalTasks.filter(t => !t.completed).length;
  const pendingJob     = leads.flatMap(l => l.tasks).filter(t => !t.completed).length;
  const totalPending   = pendingGeneral + pendingJob;

  return (
    <div className="flex flex-col h-full bg-white">
      {/* Toolbar */}
      <div className="flex items-center gap-3 px-5 py-3 bg-white border-b border-gray-100 shrink-0">
        <div>
          <p className="text-sm font-semibold text-gray-800">
            {totalPending > 0 ? `${totalPending} tasks pending` : 'All caught up!'}
          </p>
          <p className="text-xs text-gray-400">
            {pendingGeneral} general · {pendingJob} job-related
          </p>
        </div>
        <div className="flex gap-1 ml-auto">
          {(['todo', 'done', 'all'] as View[]).map(v => (
            <button key={v} onClick={() => setView(v)}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors capitalize ${
                view === v ? 'bg-orange-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
              }`}>
              {v === 'todo' ? 'To Do' : v === 'done' ? 'Done' : 'All'}
            </button>
          ))}
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-5 space-y-5">
        {/* General tasks always at the top */}
        <GeneralTasksSection view={view} />

        {/* Divider */}
        <div className="flex items-center gap-3">
          <div className="flex-1 h-px bg-gray-200" />
          <span className="text-xs font-semibold text-gray-400 uppercase tracking-wider">Job Tasks</span>
          <div className="flex-1 h-px bg-gray-200" />
        </div>

        {/* Job tasks grouped by card */}
        <JobTasksSection view={view} />
      </div>

      {selectedId && <LeadDetailPanel />}
    </div>
  );
}

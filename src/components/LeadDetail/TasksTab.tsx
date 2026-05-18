import { useState, useEffect, useRef } from 'react';
import { Plus, Trash2, CheckCircle2, Circle, ClipboardList } from 'lucide-react';
import type { Lead, Stage } from '../../types';
import { useStore } from '../../store/useStore';
import { formatDateShort } from '../../utils/helpers';

const STAGE_TASKS: Partial<Record<Stage, string[]>> = {
  'New Lead': [
    'Call customer to discuss requirements',
    'Confirm contact details',
    'Check job location / access',
  ],
  'Survey Booked': [
    'Confirm survey appointment with customer',
    'Prepare survey checklist',
    'Review job requirements before visit',
  ],
  'Quote Sent': [
    'Follow up on quote within 3 days',
    'Answer any customer questions',
    'Chase quote if no response after 7 days',
  ],
  'Won': [
    'Collect deposit',
    'Confirm start date with customer',
    'Order materials',
    'Brief the team on job details',
  ],
  'In Progress': [
    'Confirm materials delivered',
    'Daily progress check',
    'Take before & during photos',
    'Keep customer updated',
  ],
  'Completed': [
    'Final inspection with customer',
    'Take completion photos',
    'Send final invoice',
    'Collect outstanding balance',
  ],
  'Paid': [
    'File all job paperwork',
    'Request customer review / referral',
    'Update job records',
  ],
};

export default function TasksTab({ lead }: { lead: Lead }) {
  const { toggleTask, addTask, deleteTask } = useStore();
  const [newTask, setNewTask] = useState('');
  const prevStageRef = useRef<string | undefined>(undefined);

  useEffect(() => {
    const isStageChange = prevStageRef.current !== undefined && prevStageRef.current !== lead.stage;
    const isFirstLoad = prevStageRef.current === undefined;
    prevStageRef.current = lead.stage;

    if (isStageChange) {
      lead.tasks.filter(t => t.isTemplate).forEach(t => deleteTask(lead.id, t.id));
    }

    if (isFirstLoad || isStageChange) {
      const stageTasks = STAGE_TASKS[lead.stage] ?? [];
      const existingTitles = new Set(
        isStageChange ? [] : lead.tasks.filter(t => t.isTemplate).map(t => t.title)
      );
      stageTasks.forEach(title => {
        if (!existingTitles.has(title)) addTask(lead.id, title, true);
      });
    }
  }, [lead.stage]);

  const templateTasks = lead.tasks.filter(t => t.isTemplate);
  const customTasks = lead.tasks.filter(t => !t.isTemplate);

  const allTasks = lead.tasks;
  const done = allTasks.filter(t => t.completed).length;
  const pct = allTasks.length ? Math.round((done / allTasks.length) * 100) : 0;

  const handleAdd = () => {
    if (!newTask.trim()) return;
    addTask(lead.id, newTask.trim(), false);
    setNewTask('');
  };

  const renderTask = (task: Lead['tasks'][0]) => (
    <div key={task.id} className={`flex items-center gap-3 p-2 rounded-lg hover:bg-gray-50 group ${task.completed ? 'opacity-70' : ''}`}>
      <button onClick={() => toggleTask(lead.id, task.id)} className="shrink-0 text-gray-400 hover:text-orange-600">
        {task.completed
          ? <CheckCircle2 size={18} className="text-green-500" />
          : <Circle size={18} />}
      </button>
      <span className={`flex-1 text-sm ${task.completed ? 'line-through text-gray-400' : 'text-gray-700'}`}>
        {task.title}
      </span>
      {task.completedDate && (
        <span className="text-xs text-gray-400 shrink-0">{formatDateShort(task.completedDate)}</span>
      )}
      <button onClick={() => deleteTask(lead.id, task.id)}
        className="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-red-500 shrink-0 transition-opacity">
        <Trash2 size={13} />
      </button>
    </div>
  );

  return (
    <div className="p-4 space-y-4">
      {/* Progress */}
      {allTasks.length > 0 && (
        <div>
          <div className="flex items-center justify-between text-sm mb-1.5">
            <span className="font-semibold text-gray-700">{done} of {allTasks.length} tasks completed</span>
            <span className="font-bold text-orange-600">{pct}%</span>
          </div>
          <div className="w-full bg-gray-100 rounded-full h-2">
            <div className="h-2 rounded-full bg-orange-500 transition-all" style={{ width: `${pct}%` }} />
          </div>
        </div>
      )}

      {/* Stage checklist */}
      {templateTasks.length > 0 && (
        <div>
          <div className="flex items-center gap-1.5 mb-2">
            <ClipboardList size={13} className="text-orange-500" />
            <span className="text-xs font-bold text-gray-500 uppercase tracking-wide">{lead.stage} Checklist</span>
          </div>
          <div className="space-y-1">
            {templateTasks.map(renderTask)}
          </div>
        </div>
      )}

      {/* Custom tasks */}
      {(customTasks.length > 0 || templateTasks.length > 0) && (
        <div>
          {templateTasks.length > 0 && (
            <div className="flex items-center gap-1.5 mb-2">
              <Plus size={13} className="text-gray-400" />
              <span className="text-xs font-bold text-gray-500 uppercase tracking-wide">Custom Tasks</span>
            </div>
          )}
          <div className="space-y-1">
            {customTasks.map(renderTask)}
            {customTasks.length === 0 && templateTasks.length > 0 && (
              <p className="text-xs text-gray-400 text-center py-2">No custom tasks yet</p>
            )}
          </div>
        </div>
      )}

      {allTasks.length === 0 && (
        <p className="text-sm text-gray-400 text-center py-4">No tasks yet</p>
      )}

      {/* Add task */}
      <div className="flex gap-2">
        <input
          value={newTask}
          onChange={e => setNewTask(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && handleAdd()}
          placeholder="Add a custom task…"
          className="flex-1 border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
        />
        <button onClick={handleAdd}
          className="bg-orange-600 text-white px-3 py-2 rounded-lg hover:bg-orange-700 transition-colors">
          <Plus size={16} />
        </button>
      </div>
    </div>
  );
}

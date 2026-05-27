import { useState, useRef, useEffect } from 'react';
import { Search, Bell, Plus, X, Calendar, AlertTriangle, ClipboardList } from 'lucide-react';
import { useStore } from '../../store/useStore';

interface Props {
  onNewLead: () => void;
}

export default function TopBar({ onNewLead }: Props) {
  const { currentPage, searchQuery, setSearchQuery, setSelectedId, setCurrentPage, users, currentUserId, leads } = useStore();
  const isAdmin = users.find(u => u.id === currentUserId)?.role === 'admin';
  const [showNotifs, setShowNotifs] = useState(false);
  const panelRef = useRef<HTMLDivElement>(null);

  const today = new Date().toISOString().split('T')[0];

  // Surveys happening today
  const surveysToday = leads.filter(l => l.surveyDate === today);
  // Jobs with end date passed and not completed/paid
  const overdueJobs = leads.filter(l =>
    l.endDate && l.endDate < today && !['Completed', 'Paid'].includes(l.stage)
  );
  // Incomplete tasks on active jobs
  const pendingTasks = leads
    .filter(l => ['Won', 'In Progress'].includes(l.stage))
    .flatMap(l => l.tasks.filter(t => !t.completed).map(t => ({ task: t, lead: l })))
    .slice(0, 5);

  const totalCount = surveysToday.length + overdueJobs.length;

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (panelRef.current && !panelRef.current.contains(e.target as Node)) {
        setShowNotifs(false);
      }
    };
    if (showNotifs) document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [showNotifs]);

  const titles: Record<string, string> = {
    pipeline: 'Pipeline', dashboard: 'Dashboard', leads: 'Leads',
    jobs: 'Jobs', tasks: 'Tasks', calendar: 'Calendar', timesheet: 'Timesheet',
    contacts: 'Contacts', files: 'Files', reports: 'Reports', settings: 'Settings',
  };

  const openLead = (id: string) => {
    setSelectedId(id);
    setCurrentPage('jobs');
    setShowNotifs(false);
  };

  return (
    <header className="bg-white border-b border-gray-200 shrink-0 pt-safe">
      <div className="h-14 flex items-center px-3 md:px-4 gap-2 md:gap-4">
        {/* Title */}
        <h1 className="hidden sm:block text-lg font-bold text-gray-800 w-28 lg:w-32 shrink-0">
          {titles[currentPage] ?? 'Pipeline'}
        </h1>

        {/* Search */}
        <div className="flex-1 relative max-w-sm">
          <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input
            type="text"
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            placeholder="Search…"
            className="w-full pl-9 pr-8 py-1.5 rounded-lg border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-gray-50"
          />
          {searchQuery && (
            <button onClick={() => setSearchQuery('')} className="absolute right-2 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600">
              <X size={13} />
            </button>
          )}
        </div>

        <div className="ml-auto flex items-center gap-2">
          {/* Notifications bell */}
          <div className="relative" ref={panelRef}>
            <button
              onClick={() => setShowNotifs(v => !v)}
              className="relative p-2 rounded-lg hover:bg-gray-100 text-gray-500"
            >
              <Bell size={20} />
              {totalCount > 0 && (
                <span className="absolute top-0.5 right-0.5 w-4 h-4 bg-red-500 text-white text-[9px] font-bold rounded-full flex items-center justify-center">
                  {totalCount}
                </span>
              )}
            </button>

            {showNotifs && (
              <div className="absolute right-0 top-11 w-80 bg-white rounded-2xl shadow-xl border border-gray-100 z-50 overflow-hidden">
                <div className="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
                  <span className="font-bold text-gray-800 text-sm">Notifications</span>
                  <button onClick={() => setShowNotifs(false)} className="text-gray-400 hover:text-gray-600"><X size={14} /></button>
                </div>

                <div className="max-h-96 overflow-y-auto">
                  {/* Surveys today */}
                  {surveysToday.length > 0 && (
                    <div>
                      <p className="px-4 pt-3 pb-1 text-[10px] font-bold uppercase tracking-wider text-gray-400">Surveys Today</p>
                      {surveysToday.map(l => (
                        <button key={l.id} onClick={() => openLead(l.id)}
                          className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-orange-50 text-left">
                          <Calendar size={14} className="text-orange-500 shrink-0" />
                          <div className="min-w-0">
                            <p className="text-sm font-medium text-gray-800 truncate">{l.name}</p>
                            <p className="text-xs text-gray-400 truncate">{l.address}</p>
                          </div>
                        </button>
                      ))}
                    </div>
                  )}

                  {/* Overdue jobs */}
                  {overdueJobs.length > 0 && (
                    <div>
                      <p className="px-4 pt-3 pb-1 text-[10px] font-bold uppercase tracking-wider text-gray-400">Overdue</p>
                      {overdueJobs.map(l => (
                        <button key={l.id} onClick={() => openLead(l.id)}
                          className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-red-50 text-left">
                          <AlertTriangle size={14} className="text-red-500 shrink-0" />
                          <div className="min-w-0">
                            <p className="text-sm font-medium text-gray-800 truncate">{l.name}</p>
                            <p className="text-xs text-gray-400">End date: {l.endDate}</p>
                          </div>
                        </button>
                      ))}
                    </div>
                  )}

                  {/* Pending tasks */}
                  {pendingTasks.length > 0 && (
                    <div>
                      <p className="px-4 pt-3 pb-1 text-[10px] font-bold uppercase tracking-wider text-gray-400">Pending Tasks</p>
                      {pendingTasks.map(({ task, lead }) => (
                        <button key={task.id} onClick={() => openLead(lead.id)}
                          className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-gray-50 text-left">
                          <ClipboardList size={14} className="text-gray-400 shrink-0" />
                          <div className="min-w-0">
                            <p className="text-sm font-medium text-gray-800 truncate">{task.title}</p>
                            <p className="text-xs text-gray-400 truncate">{lead.name} — {lead.jobRef}</p>
                          </div>
                        </button>
                      ))}
                    </div>
                  )}

                  {totalCount === 0 && pendingTasks.length === 0 && (
                    <div className="px-4 py-8 text-center text-sm text-gray-400">
                      All clear — nothing needs attention
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>

          {isAdmin && (
            <button
              onClick={onNewLead}
              className="flex items-center gap-1 md:gap-1.5 bg-orange-600 hover:bg-orange-700 text-white text-sm font-medium px-3 py-2 rounded-lg transition-colors"
            >
              <Plus size={16} />
              <span className="hidden sm:inline">New Lead</span>
            </button>
          )}
        </div>
      </div>
    </header>
  );
}

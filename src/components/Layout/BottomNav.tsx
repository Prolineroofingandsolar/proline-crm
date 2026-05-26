import { useState } from 'react';
import { Kanban, Users, Briefcase, CheckSquare, LayoutDashboard, Calendar, Contact, FolderOpen, BarChart2, Settings, MoreHorizontal, X, Clock, Layers } from 'lucide-react';
import { useStore } from '../../store/useStore';

const ADMIN_MAIN = [
  { id: 'pipeline',  label: 'Pipeline',  icon: Kanban },
  { id: 'leads',     label: 'Leads',     icon: Users },
  { id: 'timesheet', label: 'Timesheet', icon: Clock },
  { id: 'tasks',     label: 'Tasks',     icon: CheckSquare },
];
const USER_MAIN = [
  { id: 'pipeline',  label: 'Pipeline',  icon: Kanban },
  { id: 'jobs',      label: 'Jobs',      icon: Briefcase },
  { id: 'timesheet', label: 'Timesheet', icon: Clock },
  { id: 'tasks',     label: 'Tasks',     icon: CheckSquare },
];

const ADMIN_MORE = [
  { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { id: 'calendar',  label: 'Calendar',  icon: Calendar },
  { id: 'jobs',      label: 'Jobs',      icon: Briefcase },
  { id: 'services',  label: 'Services',  icon: Layers },
  { id: 'contacts',  label: 'Contacts',  icon: Contact },
  { id: 'files',     label: 'Files',     icon: FolderOpen },
  { id: 'reports',   label: 'Reports',   icon: BarChart2 },
  { id: 'settings',  label: 'Settings',  icon: Settings },
];
const USER_MORE = [
  { id: 'calendar',  label: 'Calendar',  icon: Calendar },
  { id: 'services',  label: 'Services',  icon: Layers },
];

export default function BottomNav() {
  const { currentPage, setCurrentPage, users, currentUserId } = useStore();
  const isAdmin = users.find(u => u.id === currentUserId)?.role === 'admin';
  const MAIN = isAdmin ? ADMIN_MAIN : USER_MAIN;
  const MORE  = isAdmin ? ADMIN_MORE : USER_MORE;
  const [showMore, setShowMore] = useState(false);

  const go = (id: string) => { setCurrentPage(id); setShowMore(false); };
  const moreActive = MORE.some(n => n.id === currentPage);

  return (
    <>
      {/* More sheet overlay */}
      {showMore && (
        <>
          <div className="fixed inset-0 z-40 bg-black/30" onClick={() => setShowMore(false)} />
          <div className="fixed left-0 right-0 z-50 bg-white rounded-t-2xl shadow-2xl p-4" style={{ bottom: 'calc(64px + env(safe-area-inset-bottom, 0px))' }}>
            <div className="w-10 h-1 bg-gray-200 rounded-full mx-auto mb-4" />
            <div className="grid grid-cols-3 gap-3">
              {MORE.map(({ id, label, icon: Icon }) => (
                <button key={id} onClick={() => go(id)}
                  className={`flex flex-col items-center gap-1.5 py-3 rounded-xl text-xs font-medium transition-colors ${
                    currentPage === id ? 'bg-orange-50 text-orange-600' : 'bg-gray-50 text-gray-600 hover:bg-gray-100'
                  }`}>
                  <Icon size={22} />
                  {label}
                </button>
              ))}
            </div>
          </div>
        </>
      )}

      {/* Bottom bar */}
      <nav className="fixed bottom-0 left-0 right-0 z-40 bg-white border-t border-gray-200 flex pb-safe sm:hidden">
        {MAIN.map(({ id, label, icon: Icon }) => {
          const active = currentPage === id;
          return (
            <button key={id} onClick={() => go(id)}
              className={`flex-1 flex flex-col items-center gap-0.5 py-2 text-[10px] font-medium transition-colors ${
                active ? 'text-orange-600' : 'text-gray-400'
              }`}>
              <Icon size={22} strokeWidth={active ? 2.2 : 1.8} />
              {label}
            </button>
          );
        })}

        {/* More */}
        <button onClick={() => setShowMore(s => !s)}
          className={`flex-1 flex flex-col items-center gap-0.5 py-2 text-[10px] font-medium transition-colors ${
            moreActive || showMore ? 'text-orange-600' : 'text-gray-400'
          }`}>
          {showMore ? <X size={22} strokeWidth={2} /> : <MoreHorizontal size={22} strokeWidth={1.8} />}
          {showMore ? 'Close' : 'More'}
        </button>
      </nav>
    </>
  );
}

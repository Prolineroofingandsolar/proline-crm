import { useState } from 'react';
import { LayoutDashboard, Users, Briefcase, CheckSquare, Calendar, Contact, FolderOpen, BarChart2, Settings, ChevronDown, Kanban, LogOut } from 'lucide-react';
import { useStore } from '../../store/useStore';

const nav = [
  { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { id: 'pipeline',  label: 'Pipeline',  icon: Kanban },
  { id: 'leads',     label: 'Leads',     icon: Users },
  { id: 'jobs',      label: 'Jobs',      icon: Briefcase },
  { id: 'tasks',     label: 'Tasks',     icon: CheckSquare },
  { id: 'calendar',  label: 'Calendar',  icon: Calendar },
  { id: 'contacts',  label: 'Contacts',  icon: Contact },
  { id: 'files',     label: 'Files',     icon: FolderOpen },
  { id: 'reports',   label: 'Reports',   icon: BarChart2 },
  { id: 'settings',  label: 'Settings',  icon: Settings },
];

function ProLineLogo() {
  return (
    <svg viewBox="0 0 220 165" fill="none" xmlns="http://www.w3.org/2000/svg" className="w-full h-full">
      <polygon points="92,42 2,18 2,36" fill="#ea580c"/>
      <polygon points="92,42 2,41 2,59" fill="#ea580c"/>
      <polygon points="92,42 2,64 2,82" fill="#ea580c"/>
      <polygon points="92,42 2,87 2,105" fill="#ea580c"/>
      <path d="M92,42 L122,16 L148,68 L188,10 L188,2 L203,2 L203,10 L218,145"
            stroke="white" strokeWidth="9" strokeLinecap="round" strokeLinejoin="round"/>
      <path d="M92,42 L124,25 L150,71 L190,19 L218,131"
            stroke="white" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round"/>
      <path d="M92,42 L126,34 L152,73 L192,28 L218,117"
            stroke="white" strokeWidth="7" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  );
}

export default function Sidebar() {
  const { currentPage, setCurrentPage, users, currentUserId, logout } = useStore();
  const currentUser = users.find(u => u.id === currentUserId);
  const initial = currentUser?.name?.[0]?.toUpperCase() ?? '?';
  const [showMenu, setShowMenu] = useState(false);

  return (
    <aside className="w-16 lg:w-56 shrink-0 flex flex-col h-full transition-all duration-200" style={{ background: '#111827' }}>
      {/* Logo */}
      <div className="flex items-center justify-center lg:justify-start gap-3 px-3 lg:px-4 py-4 border-b border-white/10">
        <div className="w-10 h-8 shrink-0">
          <ProLineLogo />
        </div>
        <div className="leading-tight hidden lg:block">
          <div className="text-white font-extrabold text-sm tracking-wide">ProLine</div>
          <div className="text-orange-400 text-[11px] font-medium tracking-wider uppercase">Roofing & Solar</div>
        </div>
      </div>

      {/* Nav */}
      <nav className="flex-1 overflow-y-auto py-3 px-2">
        {nav.map(({ id, label, icon: Icon }) => {
          const active = currentPage === id;
          return (
            <button
              key={id}
              onClick={() => setCurrentPage(id)}
              title={label}
              className={`w-full flex items-center justify-center lg:justify-start gap-3 px-3 py-2.5 rounded-lg text-sm font-medium mb-0.5 transition-colors ${
                active
                  ? 'bg-orange-600 text-white'
                  : 'text-white/60 hover:bg-white/10 hover:text-white'
              }`}
            >
              <Icon size={18} className="shrink-0" />
              <span className="hidden lg:block">{label}</span>
            </button>
          );
        })}
      </nav>

      {/* Current user */}
      <div className="p-3 border-t border-white/10 relative">
        {/* Popup menu */}
        {showMenu && (
          <>
            <div className="fixed inset-0 z-40" onClick={() => setShowMenu(false)} />
            <div className="absolute bottom-full left-2 right-2 mb-2 z-50 bg-gray-800 rounded-xl shadow-xl overflow-hidden border border-white/10">
              <div className="px-4 py-3 border-b border-white/10">
                <p className="text-white text-sm font-semibold truncate">{currentUser?.name ?? 'User'}</p>
                <p className="text-white/50 text-xs capitalize">@{currentUser?.username} · {currentUser?.role}</p>
              </div>
              <button
                onClick={() => { setShowMenu(false); setCurrentPage('settings'); }}
                className="w-full flex items-center gap-2.5 px-4 py-2.5 text-white/70 hover:bg-white/10 hover:text-white text-sm transition-colors"
              >
                <Settings size={14} /> Settings
              </button>
              <button
                onClick={() => { setShowMenu(false); logout(); }}
                className="w-full flex items-center gap-2.5 px-4 py-2.5 text-red-400 hover:bg-red-500/10 hover:text-red-300 text-sm transition-colors"
              >
                <LogOut size={14} /> Sign Out
              </button>
            </div>
          </>
        )}

        <button
          onClick={() => setShowMenu(s => !s)}
          className="w-full flex items-center justify-center lg:justify-start gap-2.5 px-2 py-2 rounded-lg hover:bg-white/10 transition-colors"
        >
          <div className="w-8 h-8 rounded-full bg-orange-600 flex items-center justify-center text-white text-sm font-bold shrink-0">
            {initial}
          </div>
          <div className="hidden lg:flex flex-col text-left flex-1 min-w-0">
            <div className="text-white text-sm font-medium truncate">{currentUser?.name ?? 'User'}</div>
            <div className="text-white/50 text-xs capitalize">{currentUser?.role}</div>
          </div>
          <ChevronDown size={14} className={`text-white/40 shrink-0 hidden lg:block transition-transform ${showMenu ? 'rotate-180' : ''}`} />
        </button>
      </div>
    </aside>
  );
}

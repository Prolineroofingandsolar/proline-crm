import { LayoutDashboard, Users, Briefcase, CheckSquare, Calendar, Contact, FolderOpen, BarChart2, Settings, ChevronDown, Kanban } from 'lucide-react';
import { useStore } from '../../store/useStore';

const nav = [
  { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { id: 'pipeline', label: 'Pipeline', icon: Kanban },
  { id: 'leads', label: 'Leads', icon: Users },
  { id: 'jobs', label: 'Jobs', icon: Briefcase },
  { id: 'tasks', label: 'Tasks', icon: CheckSquare },
  { id: 'calendar', label: 'Calendar', icon: Calendar },
  { id: 'contacts', label: 'Contacts', icon: Contact },
  { id: 'files', label: 'Files', icon: FolderOpen },
  { id: 'reports', label: 'Reports', icon: BarChart2 },
  { id: 'settings', label: 'Settings', icon: Settings },
];

function ProLineLogo() {
  // Peak where orange and white sections meet: (92, 42)
  // Orange: 4 filled triangular bands fanning left from the peak
  // White: 3 parallel M-shaped roof paths going right from the peak, with chimney notch
  return (
    <svg viewBox="0 0 220 165" fill="none" xmlns="http://www.w3.org/2000/svg" className="w-full h-full">
      {/* 4 orange solar-panel bands — equal-width triangles converging at peak */}
      <polygon points="92,42 2,18 2,36" fill="#ea580c"/>
      <polygon points="92,42 2,41 2,59" fill="#ea580c"/>
      <polygon points="92,42 2,64 2,82" fill="#ea580c"/>
      <polygon points="92,42 2,87 2,105" fill="#ea580c"/>

      {/* 3 white parallel paths: inner peak → valley → outer peak → chimney → base */}
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
  const { currentPage, setCurrentPage } = useStore();

  return (
    <aside className="w-56 shrink-0 flex flex-col h-full" style={{ background: '#111827' }}>
      {/* Logo */}
      <div className="flex items-center gap-3 px-4 py-4 border-b border-white/10">
        <div className="w-10 h-8 shrink-0">
          <ProLineLogo />
        </div>
        <div className="leading-tight">
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
              className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium mb-0.5 transition-colors text-left ${
                active
                  ? 'bg-orange-600 text-white'
                  : 'text-white/60 hover:bg-white/8 hover:text-white'
              }`}
            >
              <Icon size={17} />
              {label}
            </button>
          );
        })}
      </nav>

      {/* User */}
      <div className="p-3 border-t border-white/10">
        <button className="w-full flex items-center gap-2.5 px-2 py-2 rounded-lg hover:bg-white/10 transition-colors">
          <div className="w-8 h-8 rounded-full bg-orange-600 flex items-center justify-center text-white text-sm font-bold shrink-0">
            H
          </div>
          <div className="text-left flex-1 min-w-0">
            <div className="text-white text-sm font-medium truncate">Harman</div>
            <div className="text-white/50 text-xs">Owner</div>
          </div>
          <ChevronDown size={14} className="text-white/40 shrink-0" />
        </button>
      </div>
    </aside>
  );
}

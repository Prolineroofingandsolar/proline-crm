import { Search, Bell, Plus, X } from 'lucide-react';
import { useStore } from '../../store/useStore';

interface Props {
  onNewLead: () => void;
}

export default function TopBar({ onNewLead }: Props) {
  const { currentPage, searchQuery, setSearchQuery } = useStore();

  const titles: Record<string, string> = {
    pipeline: 'Pipeline', dashboard: 'Dashboard', leads: 'Leads',
    jobs: 'Jobs', tasks: 'Tasks', calendar: 'Calendar',
    contacts: 'Contacts', files: 'Files', reports: 'Reports', settings: 'Settings',
  };

  return (
    <header className="h-14 bg-white border-b border-gray-200 flex items-center px-3 md:px-4 gap-2 md:gap-4 shrink-0">
      {/* Title — tablet and desktop */}
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
        <button className="relative p-1.5 rounded-lg hover:bg-gray-100 text-gray-500">
          <Bell size={18} />
          <span className="absolute top-0.5 right-0.5 w-4 h-4 bg-red-500 text-white text-[9px] font-bold rounded-full flex items-center justify-center">3</span>
        </button>
        <button
          onClick={onNewLead}
          className="flex items-center gap-1 md:gap-1.5 bg-orange-600 hover:bg-orange-700 text-white text-sm font-medium px-2.5 md:px-3 py-1.5 rounded-lg transition-colors"
        >
          <Plus size={15} />
          <span className="hidden sm:inline lg:inline">New Lead</span>
        </button>
      </div>
    </header>
  );
}

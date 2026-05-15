import { useState } from 'react';
import { Search, FileText, Image as ImageIcon, Archive, File } from 'lucide-react';
import { useStore } from '../store/useStore';
import { formatDate } from '../utils/helpers';
import LeadDetailPanel from '../components/LeadDetail/LeadDetailPanel';

export default function FilesPage() {
  const { leads, selectedId, setSelectedId } = useStore();
  const [search, setSearch] = useState('');

  const allFiles = leads.flatMap(l => l.files.map(f => ({ ...f, lead: l })));
  const filtered = allFiles.filter(f => !search || f.name.toLowerCase().includes(search.toLowerCase()) || f.lead.name.toLowerCase().includes(search.toLowerCase()));

  const iconMap: Record<string, React.ReactNode> = {
    pdf: <FileText size={18} className="text-red-500" />,
    image: <ImageIcon size={18} className="text-orange-500" />,
    document: <File size={18} className="text-orange-600" />,
    spreadsheet: <File size={18} className="text-green-600" />,
    archive: <Archive size={18} className="text-amber-500" />,
  };

  return (
    <div className="flex flex-col h-full bg-white">
      <div className="flex items-center gap-3 px-5 py-3 bg-white border-b border-gray-100">
        <div className="relative flex-1 max-w-xs">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search files…"
            className="w-full pl-8 pr-3 py-1.5 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-400" />
        </div>
        <span className="text-xs text-gray-400 ml-auto">{filtered.length} files</span>
      </div>

      <div className="flex-1 overflow-auto p-4">
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          <table className="w-full">
            <thead className="border-b border-gray-100">
              <tr>
                {['File', 'Customer', 'Type', 'Size', 'Date'].map(h => (
                  <th key={h} className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {filtered.map(file => (
                <tr key={file.id} className="hover:bg-gray-50 cursor-pointer" onClick={() => setSelectedId(file.lead.id)}>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      {iconMap[file.type] ?? <File size={18} className="text-gray-400" />}
                      <span className="text-sm font-medium text-gray-800">{file.name}</span>
                    </div>
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600">{file.lead.name}</td>
                  <td className="px-4 py-3 text-xs text-gray-400 uppercase">{file.type}</td>
                  <td className="px-4 py-3 text-xs text-gray-400">{file.size ?? '—'}</td>
                  <td className="px-4 py-3 text-xs text-gray-400">{formatDate(file.date)}</td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr><td colSpan={5} className="text-center py-12 text-gray-400 text-sm">No files found</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {selectedId && <LeadDetailPanel />}
    </div>
  );
}

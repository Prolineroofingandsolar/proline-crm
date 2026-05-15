import { useState } from 'react';
import { Plus, Trash2, FileText, Image as ImageIcon, Archive, File } from 'lucide-react';
import type { Lead, FileItem } from '../../types';
import { useStore } from '../../store/useStore';
import { formatDate } from '../../utils/helpers';

const iconMap: Record<string, React.ReactNode> = {
  pdf: <FileText size={18} className="text-red-500" />,
  image: <ImageIcon size={18} className="text-orange-500" />,
  document: <File size={18} className="text-orange-600" />,
  spreadsheet: <File size={18} className="text-green-600" />,
  archive: <Archive size={18} className="text-amber-500" />,
};

export default function FilesTab({ lead }: { lead: Lead }) {
  const { addFile, deleteFile } = useStore();
  const [adding, setAdding] = useState(false);
  const [form, setForm] = useState({ name: '', type: 'pdf' as FileItem['type'], size: '' });

  const handleAdd = () => {
    if (!form.name.trim()) return;
    addFile(lead.id, { name: form.name.trim(), type: form.type, size: form.size || undefined, date: new Date().toISOString().split('T')[0] });
    setForm({ name: '', type: 'pdf', size: '' });
    setAdding(false);
  };

  return (
    <div className="p-4 space-y-4">
      <div className="space-y-1.5">
        {lead.files.map(file => (
          <div key={file.id} className="flex items-center gap-3 p-2.5 rounded-xl border border-gray-100 hover:border-gray-200 bg-white group cursor-pointer">
            <div className="shrink-0">{iconMap[file.type] ?? <File size={18} className="text-gray-400" />}</div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-800 truncate">{file.name}</p>
              <p className="text-xs text-gray-400">{file.size ? `${file.size} · ` : ''}{formatDate(file.date)}</p>
            </div>
            <button onClick={() => deleteFile(lead.id, file.id)}
              className="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-red-500 shrink-0 transition-opacity">
              <Trash2 size={13} />
            </button>
          </div>
        ))}
        {lead.files.length === 0 && <p className="text-sm text-gray-400 text-center py-4">No files uploaded</p>}
      </div>

      {adding ? (
        <div className="border border-gray-200 rounded-xl p-3 space-y-2">
          <input value={form.name} onChange={e => setForm(p => ({ ...p, name: e.target.value }))}
            placeholder="File name (e.g. Quote_Customer.pdf)"
            className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
          <div className="grid grid-cols-2 gap-2">
            <select value={form.type} onChange={e => setForm(p => ({ ...p, type: e.target.value as FileItem['type'] }))}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400">
              <option value="pdf">PDF</option>
              <option value="image">Image</option>
              <option value="document">Document</option>
              <option value="spreadsheet">Spreadsheet</option>
              <option value="archive">Archive</option>
            </select>
            <input value={form.size} onChange={e => setForm(p => ({ ...p, size: e.target.value }))}
              placeholder="Size (e.g. 245 KB)"
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
          </div>
          <div className="flex gap-2">
            <button onClick={() => setAdding(false)} className="flex-1 border border-gray-200 rounded-lg py-1.5 text-sm text-gray-500 hover:bg-gray-50">Cancel</button>
            <button onClick={handleAdd} className="flex-1 bg-orange-600 text-white rounded-lg py-1.5 text-sm hover:bg-orange-700">Add File</button>
          </div>
        </div>
      ) : (
        <button onClick={() => setAdding(true)} className="flex items-center gap-2 text-sm text-orange-600 hover:text-orange-800 font-medium">
          <Plus size={15} /> Add File
        </button>
      )}
    </div>
  );
}

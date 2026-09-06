import { useState } from 'react';
import { Plus, Trash2, FileText, Image as ImageIcon, Archive, File } from 'lucide-react';
import type { Lead, FileItem } from '../../types';
import { useStore } from '../../store/useStore';
import { formatDate } from '../../utils/helpers';
import { removeStoredObject, uploadStoredObject, useStorageAsset } from '../StorageAsset';

const iconMap: Record<string, React.ReactNode> = {
  pdf: <FileText size={18} className="text-red-500" />,
  image: <ImageIcon size={18} className="text-orange-500" />,
  document: <File size={18} className="text-orange-600" />,
  spreadsheet: <File size={18} className="text-green-600" />,
  archive: <Archive size={18} className="text-amber-500" />,
};

function FileRow({ file, onDelete }: { file: FileItem; onDelete: () => void }) {
  const url = useStorageAsset(file.url);
  const content = (
    <>
      <div className="shrink-0">{iconMap[file.type] ?? <File size={18} className="text-gray-400" />}</div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium text-gray-800 truncate">{file.name}</p>
        <p className="text-xs text-gray-400">{file.size ? `${file.size} · ` : ''}{formatDate(file.date)}</p>
      </div>
    </>
  );
  return (
    <div className="flex items-center gap-3 p-2.5 rounded-xl border border-gray-100 hover:border-gray-200 bg-white group">
      {url ? <a href={url} target="_blank" rel="noreferrer" className="flex flex-1 min-w-0 items-center gap-3">{content}</a> : <div className="flex flex-1 min-w-0 items-center gap-3">{content}</div>}
      <button onClick={onDelete} aria-label={`Delete ${file.name}`} className="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-red-500 shrink-0 transition-opacity"><Trash2 size={13} /></button>
    </div>
  );
}

export default function FilesTab({ lead }: { lead: Lead }) {
  const { addFile, deleteFile } = useStore();
  const [adding, setAdding] = useState(false);
  const [file, setFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState('');
  const handleAdd = async () => {
    if (!file) return;
    setUploading(true); setError('');
    try {
      const locator = await uploadStoredObject(file, lead.id);
      const extension = file.name.split('.').pop()?.toLowerCase();
      const type: FileItem['type'] = file.type.startsWith('image/') ? 'image' : extension === 'pdf' ? 'pdf' : ['xls', 'xlsx', 'csv'].includes(extension ?? '') ? 'spreadsheet' : ['zip', 'tar', 'gz'].includes(extension ?? '') ? 'archive' : 'document';
      addFile(lead.id, { name: file.name, type, size: `${Math.max(1, Math.round(file.size / 1024))} KB`, date: new Date().toISOString().split('T')[0], url: locator });
      setFile(null); setAdding(false);
    } catch (reason) { setError(reason instanceof Error ? reason.message : 'Upload failed.'); }
    finally { setUploading(false); }
  };
  return (
    <div className="p-4 space-y-4">
      <div className="space-y-1.5">
        {lead.files.map(file => <FileRow key={file.id} file={file} onDelete={() => { deleteFile(lead.id, file.id); void removeStoredObject(file.url); }} />)}
        {lead.files.length === 0 && <p className="text-sm text-gray-400 text-center py-4">No files uploaded</p>}
      </div>
      {adding ? (
        <div className="border border-gray-200 rounded-xl p-3 space-y-2">
          <input type="file" onChange={e => setFile(e.target.files?.[0] ?? null)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm" />
          <div className="flex gap-2">
            <button disabled={uploading} onClick={() => setAdding(false)} className="flex-1 border border-gray-200 rounded-lg py-1.5 text-sm text-gray-500 hover:bg-gray-50">Cancel</button>
            <button disabled={!file || uploading} onClick={() => void handleAdd()} className="flex-1 bg-orange-600 disabled:opacity-50 text-white rounded-lg py-1.5 text-sm hover:bg-orange-700">{uploading ? 'Uploading…' : 'Upload File'}</button>
          </div>
          {error && <p className="text-xs text-red-600">{error}</p>}
        </div>
      ) : <button onClick={() => setAdding(true)} className="flex items-center gap-2 text-sm text-orange-600 hover:text-orange-800 font-medium"><Plus size={15} /> Add File</button>}
    </div>
  );
}

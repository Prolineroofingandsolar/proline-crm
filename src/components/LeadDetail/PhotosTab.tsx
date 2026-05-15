import { useState } from 'react';
import { Plus, Trash2, Image as ImageIcon } from 'lucide-react';
import type { Lead } from '../../types';
import { useStore } from '../../store/useStore';
import { formatDateShort } from '../../utils/helpers';

type Cat = 'Before' | 'During' | 'After';

export default function PhotosTab({ lead }: { lead: Lead }) {
  const { addPhoto, deletePhoto } = useStore();
  const [adding, setAdding] = useState(false);
  const [form, setForm] = useState({ url: '', caption: '', category: 'Before' as Cat });
  const categories: Cat[] = ['Before', 'During', 'After'];

  const handleAdd = () => {
    if (!form.url.trim()) return;
    addPhoto(lead.id, { url: form.url.trim(), caption: form.caption, category: form.category, date: new Date().toISOString().split('T')[0] });
    setForm({ url: '', caption: '', category: 'Before' });
    setAdding(false);
  };

  return (
    <div className="p-4 space-y-5">
      {categories.map(cat => {
        const photos = lead.photos.filter(p => p.category === cat);
        return (
          <div key={cat}>
            <h3 className="text-xs font-bold text-gray-500 uppercase tracking-wider mb-2">{cat}</h3>
            <div className="flex flex-wrap gap-2">
              {photos.map(photo => (
                <div key={photo.id} className="relative group w-24 h-24">
                  <img src={photo.url} alt={photo.caption ?? cat} className="w-24 h-24 object-cover rounded-xl" />
                  <div className="absolute inset-0 bg-black/0 group-hover:bg-black/40 rounded-xl transition-all flex items-center justify-center">
                    <button onClick={() => deletePhoto(lead.id, photo.id)}
                      className="opacity-0 group-hover:opacity-100 bg-red-500 text-white p-1.5 rounded-lg transition-opacity">
                      <Trash2 size={13} />
                    </button>
                  </div>
                  {photo.date && (
                    <p className="text-xs text-gray-400 mt-0.5 text-center">{formatDateShort(photo.date)}</p>
                  )}
                </div>
              ))}
              {photos.length === 0 && (
                <div className="w-24 h-24 rounded-xl border-2 border-dashed border-gray-200 flex flex-col items-center justify-center text-gray-300">
                  <ImageIcon size={20} />
                  <span className="text-xs mt-1">None</span>
                </div>
              )}
            </div>
          </div>
        );
      })}

      {/* Add photo */}
      {adding ? (
        <div className="border border-gray-200 rounded-xl p-3 space-y-2">
          <select value={form.category} onChange={e => setForm(p => ({ ...p, category: e.target.value as Cat }))}
            className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400">
            {categories.map(c => <option key={c}>{c}</option>)}
          </select>
          <input value={form.url} onChange={e => setForm(p => ({ ...p, url: e.target.value }))}
            placeholder="Image URL or paste link"
            className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
          <input value={form.caption} onChange={e => setForm(p => ({ ...p, caption: e.target.value }))}
            placeholder="Caption (optional)"
            className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
          <div className="flex gap-2">
            <button onClick={() => setAdding(false)} className="flex-1 border border-gray-200 rounded-lg py-1.5 text-sm text-gray-500 hover:bg-gray-50">Cancel</button>
            <button onClick={handleAdd} className="flex-1 bg-orange-600 text-white rounded-lg py-1.5 text-sm hover:bg-orange-700">Add Photo</button>
          </div>
        </div>
      ) : (
        <button onClick={() => setAdding(true)}
          className="flex items-center gap-2 text-sm text-orange-600 hover:text-orange-800 font-medium">
          <Plus size={15} /> Add Photo
        </button>
      )}
    </div>
  );
}

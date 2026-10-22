import { useState } from 'react';
import { X, Loader2, Send } from 'lucide-react';
import type { PaperclipAgent } from '../../lib/paperclip';

interface Props {
  agent: PaperclipAgent;
  onSubmit: (title: string, description: string) => Promise<void>;
  onClose: () => void;
}

export default function NewTaskModal({ agent, onSubmit, onClose }: Props) {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim()) return;
    setSaving(true);
    setError('');
    try {
      await onSubmit(title.trim(), description.trim());
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not create the task');
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 z-[60] flex items-end md:items-center justify-center bg-black/40 backdrop-blur-sm md:p-4">
      <form onSubmit={handleSubmit} className="bg-white md:rounded-2xl rounded-t-2xl shadow-2xl w-full md:max-w-lg max-h-[92dvh] flex flex-col">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100 shrink-0">
          <h2 className="font-bold text-gray-800 text-lg">Give {agent.name} a task</h2>
          <button type="button" onClick={onClose} className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-500"><X size={18} /></button>
        </div>
        <div className="p-5 space-y-4 overflow-y-auto">
          <div>
            <label className="block text-xs font-medium text-gray-600 mb-1">What should they do?</label>
            <input autoFocus required value={title} onChange={e => setTitle(e.target.value)}
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
              placeholder="e.g. Draft follow-up emails for this week's roof surveys" />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-600 mb-1">Details (optional)</label>
            <textarea value={description} onChange={e => setDescription(e.target.value)} rows={5}
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
              placeholder="Anything they need to know: context, links, what done looks like…" />
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
        </div>
        <div className="flex justify-end gap-2 px-5 py-4 border-t border-gray-100 shrink-0">
          <button type="button" onClick={onClose} className="px-4 py-2 rounded-lg text-sm text-gray-600 hover:bg-gray-100">Cancel</button>
          <button type="submit" disabled={saving || !title.trim()}
            className="flex items-center gap-1.5 px-4 py-2 rounded-lg text-sm font-semibold bg-orange-600 hover:bg-orange-700 text-white disabled:opacity-50">
            {saving ? <Loader2 size={15} className="animate-spin" /> : <Send size={15} />}
            Assign task
          </button>
        </div>
      </form>
    </div>
  );
}

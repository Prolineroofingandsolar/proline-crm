import { useState } from 'react';
import { Trash2, MessageSquare } from 'lucide-react';
import type { Lead } from '../../types';
import { useStore } from '../../store/useStore';
import { formatDate } from '../../utils/helpers';

export default function NotesTab({ lead }: { lead: Lead }) {
  const { addNote, deleteNote } = useStore();
  const [text, setText] = useState('');

  const handleAdd = () => {
    if (!text.trim()) return;
    addNote(lead.id, text.trim());
    setText('');
  };

  // Normalise each note so a legacy record (e.g. stored as a plain string, or
  // missing fields) renders as text instead of throwing during render.
  const notes = (Array.isArray(lead.notes) ? lead.notes : []).map(n => {
    if (typeof n === 'string') return { id: '', content: n, date: '', author: '' };
    return {
      id: typeof n?.id === 'string' ? n.id : '',
      content: typeof n?.content === 'string' ? n.content : String(n?.content ?? ''),
      date: typeof n?.date === 'string' ? n.date : '',
      author: typeof n?.author === 'string' ? n.author : '',
    };
  });

  return (
    <div className="p-4 space-y-4">
      {/* Add note */}
      <div className="space-y-2">
        <textarea
          value={text}
          onChange={e => setText(e.target.value)}
          placeholder="Add a note…"
          rows={3}
          className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 resize-none"
        />
        <button onClick={handleAdd} disabled={!text.trim()}
          className="bg-orange-600 disabled:opacity-40 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-orange-700 transition-colors">
          Add Note
        </button>
      </div>

      {/* Notes list — tolerate legacy/malformed records so a bad note can't
          crash the whole tab. */}
      <div className="space-y-3">
        {notes.map((note, i) => (
          <div key={note.id || i} className="bg-amber-50 border border-amber-100 rounded-xl p-3 group">
            <div className="flex items-start justify-between gap-2">
              <div className="flex items-center gap-2 mb-1">
                <MessageSquare size={13} className="text-amber-500 shrink-0 mt-0.5" />
                <span className="text-xs font-semibold text-amber-700">{note.author || 'Unknown'}</span>
                <span className="text-xs text-gray-400">{formatDate(note.date)}</span>
              </div>
              {note.id && (
                <button onClick={() => deleteNote(lead.id, note.id)}
                  className="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-red-500 shrink-0 transition-opacity">
                  <Trash2 size={13} />
                </button>
              )}
            </div>
            <p className="text-sm text-gray-700 whitespace-pre-wrap">{note.content}</p>
          </div>
        ))}
        {notes.length === 0 && (
          <p className="text-sm text-gray-400 text-center py-4">No notes yet</p>
        )}
      </div>
    </div>
  );
}

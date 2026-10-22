import { useState } from 'react';
import { Bot, Save } from 'lucide-react';
import { useStore } from '../../store/useStore';
import { usePaperclipStore } from '../../store/usePaperclipStore';
import { DEFAULT_PAPERCLIP_URL, getPaperclipKey, getPaperclipUrl, setPaperclipKey, setPaperclipUrl } from '../../lib/paperclip';

export default function VirtualOfficeSettings() {
  const { showToast } = useStore();
  const refresh = usePaperclipStore(s => s.refresh);
  const [url, setUrl] = useState(getPaperclipUrl());
  const [key, setKey] = useState(getPaperclipKey());

  const save = () => {
    setPaperclipUrl(url || DEFAULT_PAPERCLIP_URL);
    setPaperclipKey(key);
    showToast('Virtual Office settings saved', 'success');
    void refresh();
  };

  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
      <div className="flex items-center gap-2 px-5 py-4 border-b border-gray-100">
        <Bot size={18} className="text-orange-500" />
        <h2 className="font-bold text-gray-800">Virtual Office</h2>
      </div>
      <div className="p-5 space-y-4">
        <p className="text-sm text-gray-500">Connect ProLine to Paperclip, the app that runs your AI agents, so you can watch and manage them in the Virtual Office.</p>
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">Paperclip address</label>
          <input value={url} onChange={e => setUrl(e.target.value)} placeholder={DEFAULT_PAPERCLIP_URL}
            className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">Board API key (only if Paperclip asks you to sign in)</label>
          <input type="password" value={key} onChange={e => setKey(e.target.value)} placeholder="Leave blank for a local Paperclip"
            className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
        </div>
        <button onClick={save}
          className="flex items-center gap-1.5 px-4 py-2 rounded-lg text-sm font-semibold bg-orange-600 hover:bg-orange-700 text-white">
          <Save size={15} /> Save
        </button>
      </div>
    </div>
  );
}

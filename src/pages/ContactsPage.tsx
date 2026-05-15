import { useState } from 'react';
import { Phone, Mail, MessageSquare, Search } from 'lucide-react';
import { useStore } from '../store/useStore';
import { jobTypeColor } from '../utils/helpers';
import LeadDetailPanel from '../components/LeadDetail/LeadDetailPanel';

export default function ContactsPage() {
  const { leads, selectedId, setSelectedId } = useStore();
  const [search, setSearch] = useState('');

  // Deduplicate by phone
  const contacts = Object.values(
    leads.reduce((acc, l) => {
      if (!acc[l.phone]) acc[l.phone] = { ...l, jobCount: 1 };
      else acc[l.phone].jobCount = (acc[l.phone].jobCount ?? 1) + 1;
      return acc;
    }, {} as Record<string, typeof leads[0] & { jobCount?: number }>)
  );

  const filtered = contacts.filter(c =>
    !search ||
    c.name.toLowerCase().includes(search.toLowerCase()) ||
    c.phone.includes(search) ||
    c.email.toLowerCase().includes(search.toLowerCase()) ||
    c.address.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="flex flex-col h-full bg-white">
      <div className="flex items-center gap-3 px-5 py-3 bg-white border-b border-gray-100">
        <div className="relative flex-1 max-w-xs">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search contacts…"
            className="w-full pl-8 pr-3 py-1.5 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-400" />
        </div>
        <span className="text-xs text-gray-400 ml-auto">{filtered.length} contacts</span>
      </div>

      <div className="flex-1 overflow-auto p-4">
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
          {filtered.map(contact => (
            <div key={contact.phone}
              className="bg-white rounded-2xl border border-gray-100 p-4 hover:shadow-md hover:border-orange-200 transition-all cursor-pointer"
              onClick={() => setSelectedId(contact.id)}>
              <div className="flex items-center gap-3 mb-3">
                <div className="w-12 h-12 rounded-full bg-gradient-to-br from-orange-400 to-purple-500 flex items-center justify-center text-white font-bold text-lg shrink-0">
                  {contact.name[0]}
                </div>
                <div className="min-w-0">
                  <p className="font-bold text-gray-800 truncate">{contact.name}</p>
                  <span className={`text-xs font-medium px-1.5 py-0.5 rounded ${jobTypeColor(contact.jobType)}`}>{contact.jobType}</span>
                </div>
              </div>
              <div className="space-y-1 text-xs text-gray-500 mb-3">
                <p className="truncate">{contact.phone}</p>
                <p className="truncate">{contact.email}</p>
                <p className="truncate">{contact.address}</p>
              </div>
              {contact.jobCount && contact.jobCount > 1 && (
                <p className="text-xs text-orange-600 font-medium mb-2">{contact.jobCount} jobs</p>
              )}
              <div className="flex gap-2" onClick={e => e.stopPropagation()}>
                <a href={`tel:${contact.phone}`}
                  className="flex-1 flex items-center justify-center gap-1 py-1.5 rounded-lg bg-gray-50 hover:bg-gray-100 text-gray-600 text-xs font-medium">
                  <Phone size={12} /> Call
                </a>
                <a href={`https://wa.me/${contact.phone.replace(/\s/g, '')}`} target="_blank" rel="noreferrer"
                  className="flex-1 flex items-center justify-center gap-1 py-1.5 rounded-lg bg-green-50 hover:bg-green-100 text-green-700 text-xs font-medium">
                  <MessageSquare size={12} /> WhatsApp
                </a>
                <a href={`mailto:${contact.email}`}
                  className="flex-1 flex items-center justify-center gap-1 py-1.5 rounded-lg bg-orange-50 hover:bg-orange-100 text-orange-700 text-xs font-medium">
                  <Mail size={12} /> Email
                </a>
              </div>
            </div>
          ))}
          {filtered.length === 0 && (
            <div className="col-span-full text-center py-12 text-gray-400 text-sm">No contacts found</div>
          )}
        </div>
      </div>

      {selectedId && <LeadDetailPanel />}
    </div>
  );
}

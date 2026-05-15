import { useState } from 'react';
import { Phone, Mail, MessageSquare, Search, Trash2 } from 'lucide-react';
import { useStore } from '../store/useStore';
import LeadDetailPanel from '../components/LeadDetail/LeadDetailPanel';

export default function ContactsPage() {
  const { contacts, leads, selectedId, setSelectedId, deleteContact } = useStore();
  const [search, setSearch] = useState('');

  const filtered = contacts.filter(c =>
    !search ||
    c.name.toLowerCase().includes(search.toLowerCase()) ||
    c.phone.includes(search) ||
    c.email.toLowerCase().includes(search.toLowerCase()) ||
    c.address.toLowerCase().includes(search.toLowerCase())
  );

  // Count jobs per phone
  const jobCount = leads.reduce((acc, l) => {
    acc[l.phone] = (acc[l.phone] ?? 0) + 1;
    return acc;
  }, {} as Record<string, number>);

  // Find the most recent lead for a contact to open in panel
  const latestLead = (phone: string) =>
    leads.filter(l => l.phone === phone).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))[0];

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
          {filtered.map(contact => {
            const jobs = jobCount[contact.phone] ?? 0;
            const lead = latestLead(contact.phone);
            return (
              <div key={contact.id}
                className="bg-white rounded-2xl border border-gray-100 p-4 hover:shadow-md hover:border-orange-200 transition-all cursor-pointer"
                onClick={() => lead && setSelectedId(lead.id)}>
                <div className="flex items-center gap-3 mb-3">
                  <div className="w-12 h-12 rounded-full bg-gradient-to-br from-orange-400 to-purple-500 flex items-center justify-center text-white font-bold text-lg shrink-0">
                    {contact.name[0]}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="font-bold text-gray-800 truncate">{contact.name}</p>
                    {jobs > 0 && (
                      <p className="text-xs text-orange-600 font-medium">{jobs} job{jobs > 1 ? 's' : ''}</p>
                    )}
                  </div>
                  <button onClick={e => { e.stopPropagation(); deleteContact(contact.id); }}
                    className="p-1.5 rounded-lg hover:bg-red-50 text-gray-300 hover:text-red-500 transition-colors shrink-0">
                    <Trash2 size={14} />
                  </button>
                </div>
                <div className="space-y-1 text-xs text-gray-500 mb-3">
                  <p className="truncate">{contact.phone}</p>
                  {contact.email && <p className="truncate">{contact.email}</p>}
                  {contact.address && <p className="truncate">{contact.address}</p>}
                </div>
                <div className="flex gap-2" onClick={e => e.stopPropagation()}>
                  <a href={`tel:${contact.phone}`}
                    className="flex-1 flex items-center justify-center gap-1 py-1.5 rounded-lg bg-gray-50 hover:bg-gray-100 text-gray-600 text-xs font-medium">
                    <Phone size={12} /> Call
                  </a>
                  <a href={`https://wa.me/${contact.phone.replace(/\D/g, '')}`} target="_blank" rel="noreferrer"
                    className="flex-1 flex items-center justify-center gap-1 py-1.5 rounded-lg bg-green-50 hover:bg-green-100 text-green-700 text-xs font-medium">
                    <MessageSquare size={12} /> WhatsApp
                  </a>
                  <a href={`mailto:${contact.email}`}
                    className="flex-1 flex items-center justify-center gap-1 py-1.5 rounded-lg bg-orange-50 hover:bg-orange-100 text-orange-700 text-xs font-medium">
                    <Mail size={12} /> Email
                  </a>
                </div>
              </div>
            );
          })}
          {filtered.length === 0 && (
            <div className="col-span-full text-center py-12 text-gray-400 text-sm">No contacts found</div>
          )}
        </div>
      </div>

      {selectedId && <LeadDetailPanel />}
    </div>
  );
}

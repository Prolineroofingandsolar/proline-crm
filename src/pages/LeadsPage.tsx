import { useState } from 'react';
import { Phone, Mail, Trophy, ChevronRight, Trash2, Search } from 'lucide-react';
import { useStore } from '../store/useStore';
import { formatCurrency, formatDate, jobTypeColor } from '../utils/helpers';
import AddLeadModal from '../components/Pipeline/AddLeadModal';
import LeadDetailPanel from '../components/LeadDetail/LeadDetailPanel';

const LEAD_STAGES = ['New Lead', 'Survey Booked', 'Quote Sent'];

export default function LeadsPage() {
  const { leads, selectedId, setSelectedId, moveToStage, markAsWon, deleteLead } = useStore();
  const [showAdd, setShowAdd] = useState(false);
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState('All');

  const openLeads = leads.filter(l => LEAD_STAGES.includes(l.stage));
  const filtered = openLeads.filter(l => {
    const matchSearch = !search || l.name.toLowerCase().includes(search.toLowerCase()) || l.phone.includes(search);
    const matchFilter = filter === 'All' || l.stage === filter;
    return matchSearch && matchFilter;
  });

  return (
    <div className="flex flex-col h-full bg-white">
      {/* Toolbar */}
      <div className="flex items-center gap-3 px-5 py-3 bg-white border-b border-gray-100">
        <div className="relative flex-1 max-w-xs">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search leads…"
            className="w-full pl-8 pr-3 py-1.5 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-400" />
        </div>
        <div className="flex gap-1">
          {['All', ...LEAD_STAGES].map(s => (
            <button key={s} onClick={() => setFilter(s)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors ${filter === s ? 'bg-orange-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
              {s}
            </button>
          ))}
        </div>
        <button onClick={() => setShowAdd(true)} className="ml-auto bg-orange-600 text-white px-4 py-1.5 rounded-lg text-sm font-medium hover:bg-orange-700">
          + Add Lead
        </button>
      </div>

      {/* Table */}
      <div className="flex-1 overflow-auto">
        <table className="w-full">
          <thead className="bg-white border-b border-gray-100 sticky top-0">
            <tr>
              {['Customer', 'Job Type', 'Location', 'Stage', 'Value', 'Created', 'Actions'].map(h => (
                <th key={h} className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-50">
            {filtered.map(lead => (
              <tr key={lead.id} className="hover:bg-white cursor-pointer" onClick={() => setSelectedId(lead.id)}>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <div className="w-8 h-8 rounded-full bg-orange-100 flex items-center justify-center text-orange-700 font-bold text-xs shrink-0">
                      {lead.name[0]}
                    </div>
                    <div>
                      <p className="text-sm font-semibold text-gray-800">{lead.name}</p>
                      <p className="text-xs text-gray-400">{lead.jobRef}</p>
                    </div>
                  </div>
                </td>
                <td className="px-4 py-3">
                  <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${jobTypeColor(lead.jobType)}`}>{lead.jobType}</span>
                </td>
                <td className="px-4 py-3 text-sm text-gray-600">{lead.address.split(',').slice(-2).join(',').trim()}</td>
                <td className="px-4 py-3">
                  <span className="text-xs font-medium px-2 py-0.5 rounded-full bg-violet-100 text-violet-700">{lead.stage}</span>
                </td>
                <td className="px-4 py-3 text-sm font-semibold text-gray-700">{lead.value > 0 ? formatCurrency(lead.value) : '—'}</td>
                <td className="px-4 py-3 text-sm text-gray-400">{formatDate(lead.createdAt)}</td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-1" onClick={e => e.stopPropagation()}>
                    <a href={`tel:${lead.phone}`} className="p-1.5 rounded-lg bg-gray-50 hover:bg-gray-100 text-gray-500"><Phone size={13} /></a>
                    <a href={`mailto:${lead.email}`} className="p-1.5 rounded-lg bg-gray-50 hover:bg-gray-100 text-gray-500"><Mail size={13} /></a>
                    {lead.stage === 'Quote Sent' ? (
                      <button onClick={() => markAsWon(lead.id)} className="flex items-center gap-1 px-2 py-1 rounded-lg bg-green-50 text-green-700 hover:bg-green-100 text-xs font-medium">
                        <Trophy size={11} /> Won
                      </button>
                    ) : (
                      <button onClick={() => moveToStage(lead.id, lead.stage === 'New Lead' ? 'Survey Booked' : 'Quote Sent')}
                        className="flex items-center gap-1 px-2 py-1 rounded-lg bg-orange-50 text-orange-700 hover:bg-orange-100 text-xs font-medium">
                        <ChevronRight size={11} /> Move
                      </button>
                    )}
                    <button onClick={() => deleteLead(lead.id)} className="p-1.5 rounded-lg hover:bg-red-50 text-gray-400 hover:text-red-500">
                      <Trash2 size={13} />
                    </button>
                  </div>
                </td>
              </tr>
            ))}
            {filtered.length === 0 && (
              <tr><td colSpan={7} className="text-center py-12 text-gray-400 text-sm">No leads found</td></tr>
            )}
          </tbody>
        </table>
      </div>

      {selectedId && <LeadDetailPanel />}
      {showAdd && <AddLeadModal onClose={() => setShowAdd(false)} />}
    </div>
  );
}

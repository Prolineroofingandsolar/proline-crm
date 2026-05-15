import { useState } from 'react';
import { Phone, Mail, CheckCircle, CreditCard, Trash2, Search } from 'lucide-react';
import { useStore } from '../store/useStore';
import { formatCurrency, formatDate, jobTypeColor } from '../utils/helpers';
import LeadDetailPanel from '../components/LeadDetail/LeadDetailPanel';

const JOB_STAGES = ['Won', 'In Progress', 'Completed', 'Paid'];

export default function JobsPage() {
  const { leads, selectedId, setSelectedId, moveToStage, deleteLead } = useStore();
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState('All');

  const jobs = leads.filter(l => JOB_STAGES.includes(l.stage));
  const filtered = jobs.filter(l => {
    const matchSearch = !search || l.name.toLowerCase().includes(search.toLowerCase()) || l.jobRef.toLowerCase().includes(search.toLowerCase());
    const matchFilter = filter === 'All' || l.stage === filter;
    return matchSearch && matchFilter;
  });

  const totalValue = filtered.reduce((s, l) => s + l.value, 0);
  const totalBalance = filtered.reduce((s, l) => s + l.balance, 0);

  return (
    <div className="flex flex-col h-full bg-white">
      {/* Toolbar */}
      <div className="flex items-center gap-3 px-5 py-3 bg-white border-b border-gray-100">
        <div className="relative flex-1 max-w-xs">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search jobs…"
            className="w-full pl-8 pr-3 py-1.5 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-400" />
        </div>
        <div className="flex gap-1">
          {['All', ...JOB_STAGES].map(s => (
            <button key={s} onClick={() => setFilter(s)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors ${filter === s ? 'bg-orange-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
              {s}
            </button>
          ))}
        </div>
      </div>

      {/* Summary bar */}
      <div className="flex gap-6 px-5 py-2 bg-white border-b border-gray-100 text-xs text-gray-500">
        <span>{filtered.length} jobs</span>
        <span>Total value: <strong className="text-gray-700">{formatCurrency(totalValue)}</strong></span>
        <span>Outstanding: <strong className="text-red-600">{formatCurrency(totalBalance)}</strong></span>
      </div>

      {/* Table */}
      <div className="flex-1 overflow-auto">
        <table className="w-full">
          <thead className="bg-white border-b border-gray-100 sticky top-0">
            <tr>
              {['Job Ref', 'Customer', 'Job Type', 'Stage', 'Value', 'Balance', 'Progress', 'Start Date', 'Actions'].map(h => (
                <th key={h} className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-50">
            {filtered.map(lead => (
              <tr key={lead.id} className="hover:bg-white cursor-pointer" onClick={() => setSelectedId(lead.id)}>
                <td className="px-4 py-3 text-xs font-mono text-gray-400">{lead.jobRef}</td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <div className="w-7 h-7 rounded-full bg-orange-100 flex items-center justify-center text-orange-700 font-bold text-xs shrink-0">
                      {lead.name[0]}
                    </div>
                    <p className="text-sm font-semibold text-gray-800">{lead.name}</p>
                  </div>
                </td>
                <td className="px-4 py-3">
                  <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${jobTypeColor(lead.jobType)}`}>{lead.jobType}</span>
                </td>
                <td className="px-4 py-3">
                  <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                    lead.stage === 'Paid' ? 'bg-teal-100 text-teal-700' :
                    lead.stage === 'Completed' ? 'bg-emerald-100 text-emerald-700' :
                    lead.stage === 'In Progress' ? 'bg-orange-100 text-orange-700' :
                    'bg-green-100 text-green-700'
                  }`}>{lead.stage}</span>
                </td>
                <td className="px-4 py-3 text-sm font-semibold text-gray-700">{formatCurrency(lead.value)}</td>
                <td className={`px-4 py-3 text-sm font-semibold ${lead.balance > 0 ? 'text-red-600' : 'text-green-600'}`}>
                  {lead.balance > 0 ? formatCurrency(lead.balance) : '✓ Paid'}
                </td>
                <td className="px-4 py-3">
                  {lead.stage === 'In Progress' ? (
                    <div className="flex items-center gap-2">
                      <div className="w-16 bg-gray-100 rounded-full h-1.5">
                        <div className="h-1.5 rounded-full bg-orange-500" style={{ width: `${lead.progress}%` }} />
                      </div>
                      <span className="text-xs text-gray-500">{lead.progress}%</span>
                    </div>
                  ) : <span className="text-xs text-gray-300">—</span>}
                </td>
                <td className="px-4 py-3 text-sm text-gray-400">{formatDate(lead.startDate)}</td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-1" onClick={e => e.stopPropagation()}>
                    <a href={`tel:${lead.phone}`} className="p-1.5 rounded-lg bg-gray-50 hover:bg-gray-100 text-gray-500"><Phone size={13} /></a>
                    <a href={`mailto:${lead.email}`} className="p-1.5 rounded-lg bg-gray-50 hover:bg-gray-100 text-gray-500"><Mail size={13} /></a>
                    {lead.stage === 'In Progress' && (
                      <button onClick={() => moveToStage(lead.id, 'Completed')} className="flex items-center gap-1 px-2 py-1 rounded-lg bg-emerald-50 text-emerald-700 hover:bg-emerald-100 text-xs font-medium">
                        <CheckCircle size={11} /> Complete
                      </button>
                    )}
                    {lead.stage === 'Completed' && (
                      <button onClick={() => moveToStage(lead.id, 'Paid')} className="flex items-center gap-1 px-2 py-1 rounded-lg bg-green-50 text-green-700 hover:bg-green-100 text-xs font-medium">
                        <CreditCard size={11} /> Paid
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
              <tr><td colSpan={9} className="text-center py-12 text-gray-400 text-sm">No jobs found</td></tr>
            )}
          </tbody>
        </table>
      </div>

      {selectedId && <LeadDetailPanel />}
    </div>
  );
}

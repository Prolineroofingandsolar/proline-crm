import { useStore } from '../store/useStore';
import { formatCurrency } from '../utils/helpers';
import { TrendingUp, PoundSterling, Users, Briefcase } from 'lucide-react';

export default function ReportsPage() {
  const { leads } = useStore();

  const byStage = ['New Lead','Survey Booked','Quote Sent','Won','In Progress','Completed','Paid'].map(stage => ({
    stage,
    count: leads.filter(l => l.stage === stage).length,
    value: leads.filter(l => l.stage === stage).reduce((s, l) => s + l.value, 0),
  }));

  const byJobType = [...new Set(leads.map(l => l.jobType))].map(jt => ({
    type: jt,
    count: leads.filter(l => l.jobType === jt).length,
    value: leads.filter(l => l.jobType === jt).reduce((s, l) => s + l.value, 0),
  })).sort((a, b) => b.value - a.value);

  const bySource = [...new Set(leads.map(l => l.source))].map(src => ({
    source: src,
    count: leads.filter(l => l.source === src).length,
  })).sort((a, b) => b.count - a.count);

  const totalRevenue = leads.filter(l => l.stage === 'Paid').reduce((s, l) => s + l.value, 0);
  const totalPipeline = leads.filter(l => !['New Lead','Survey Booked'].includes(l.stage)).reduce((s, l) => s + l.value, 0);
  const avgJobValue = leads.filter(l => l.value > 0).length
    ? leads.filter(l => l.value > 0).reduce((s, l) => s + l.value, 0) / leads.filter(l => l.value > 0).length
    : 0;
  const convRate = leads.length
    ? Math.round(leads.filter(l => ['Won','In Progress','Completed','Paid'].includes(l.stage)).length / leads.length * 100)
    : 0;

  const maxCount = Math.max(...byStage.map(s => s.count), 1);

  return (
    <div className="p-6 overflow-y-auto h-full bg-white space-y-6">
      {/* KPIs */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {[
          { icon: <PoundSterling size={20} className="text-green-600" />, label: 'Total Revenue', value: formatCurrency(totalRevenue), bg: 'bg-green-50' },
          { icon: <TrendingUp size={20} className="text-orange-600" />, label: 'Pipeline Value', value: formatCurrency(totalPipeline), bg: 'bg-orange-50' },
          { icon: <Briefcase size={20} className="text-orange-600" />, label: 'Avg Job Value', value: formatCurrency(avgJobValue), bg: 'bg-orange-50' },
          { icon: <Users size={20} className="text-amber-600" />, label: 'Conversion Rate', value: `${convRate}%`, bg: 'bg-amber-50' },
        ].map(({ icon, label, value, bg }) => (
          <div key={label} className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex items-center gap-3">
            <div className={`w-10 h-10 rounded-xl ${bg} flex items-center justify-center shrink-0`}>{icon}</div>
            <div>
              <p className="text-xs text-gray-500 font-medium">{label}</p>
              <p className="text-lg font-bold text-gray-800">{value}</p>
            </div>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Pipeline funnel */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
          <h2 className="font-bold text-gray-800 mb-4">Pipeline Funnel</h2>
          <div className="space-y-3">
            {byStage.map(({ stage, count, value }) => (
              <div key={stage}>
                <div className="flex items-center justify-between text-sm mb-1">
                  <span className="text-gray-600 font-medium">{stage}</span>
                  <div className="flex items-center gap-3">
                    <span className="font-bold text-gray-800">{count}</span>
                    {value > 0 && <span className="text-xs text-gray-400">{formatCurrency(value)}</span>}
                  </div>
                </div>
                <div className="w-full bg-gray-100 rounded-full h-3">
                  <div className="h-3 rounded-full bg-gradient-to-r from-orange-400 to-orange-600 transition-all"
                    style={{ width: `${(count / maxCount) * 100}%` }} />
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* By job type */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
          <h2 className="font-bold text-gray-800 mb-4">Revenue by Job Type</h2>
          <div className="space-y-3">
            {byJobType.map(({ type, count, value }) => {
              const maxVal = Math.max(...byJobType.map(t => t.value), 1);
              return (
                <div key={type}>
                  <div className="flex items-center justify-between text-sm mb-1">
                    <span className="text-gray-600">{type}</span>
                    <div className="flex items-center gap-3">
                      <span className="text-xs text-gray-400">{count} jobs</span>
                      <span className="font-bold text-gray-800">{formatCurrency(value)}</span>
                    </div>
                  </div>
                  <div className="w-full bg-gray-100 rounded-full h-2.5">
                    <div className="h-2.5 rounded-full bg-gradient-to-r from-green-400 to-emerald-600 transition-all"
                      style={{ width: `${(value / maxVal) * 100}%` }} />
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Lead sources */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
          <h2 className="font-bold text-gray-800 mb-4">Lead Sources</h2>
          <div className="space-y-2">
            {bySource.map(({ source, count }) => {
              const maxSrc = Math.max(...bySource.map(s => s.count), 1);
              const pct = Math.round(count / leads.length * 100);
              return (
                <div key={source} className="flex items-center gap-3">
                  <span className="text-sm text-gray-600 w-28 shrink-0">{source}</span>
                  <div className="flex-1 bg-gray-100 rounded-full h-2.5">
                    <div className="h-2.5 rounded-full bg-gradient-to-r from-purple-400 to-orange-500 transition-all"
                      style={{ width: `${(count / maxSrc) * 100}%` }} />
                  </div>
                  <span className="text-sm font-bold text-gray-700 w-6 text-right">{count}</span>
                  <span className="text-xs text-gray-400 w-8 text-right">{pct}%</span>
                </div>
              );
            })}
          </div>
        </div>

        {/* Outstanding */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
          <h2 className="font-bold text-gray-800 mb-4">Outstanding Balances</h2>
          <div className="space-y-2">
            {leads.filter(l => l.balance > 0 && ['In Progress','Completed','Won'].includes(l.stage)).map(lead => (
              <div key={lead.id} className="flex items-center gap-3 p-2 rounded-lg hover:bg-gray-50">
                <div className="w-8 h-8 rounded-full bg-red-100 text-red-700 flex items-center justify-center font-bold text-xs shrink-0">
                  {lead.name[0]}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold text-gray-800 truncate">{lead.name}</p>
                  <p className="text-xs text-gray-400">{lead.jobRef} · {lead.stage}</p>
                </div>
                <span className="text-sm font-bold text-red-600 shrink-0">{formatCurrency(lead.balance)}</span>
              </div>
            ))}
            {leads.filter(l => l.balance > 0 && ['In Progress','Completed','Won'].includes(l.stage)).length === 0 && (
              <p className="text-sm text-gray-400 text-center py-4">No outstanding balances</p>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

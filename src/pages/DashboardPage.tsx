import { TrendingUp, Briefcase, PoundSterling, CheckCircle2, Clock, Trophy, Users, Star } from 'lucide-react';
import { useStore } from '../store/useStore';
import { formatCurrency, formatDate, jobTypeColor } from '../utils/helpers';
import JobsMap from '../components/Map/JobsMap';

export default function DashboardPage() {
  const { leads } = useStore();

  const stats = {
    totalLeads: leads.filter(l => ['New Lead', 'Survey Booked', 'Quote Sent'].includes(l.stage)).length,
    activeJobs: leads.filter(l => l.stage === 'In Progress').length,
    revenue: leads.filter(l => l.stage === 'Paid').reduce((s, l) => s + l.value, 0),
    pipeline: leads.filter(l => ['Won', 'In Progress', 'Completed'].includes(l.stage)).reduce((s, l) => s + l.value, 0),
    won: leads.filter(l => l.stage === 'Won').length,
    completed: leads.filter(l => l.stage === 'Completed').length,
    convRate: leads.length ? Math.round(leads.filter(l => ['Won','In Progress','Completed','Paid'].includes(l.stage)).length / leads.length * 100) : 0,
  };

  const recentLeads = [...leads].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)).slice(0, 8);
  const upcomingSurveys = leads.filter(l => l.surveyDate).sort((a, b) => (a.surveyDate ?? '').localeCompare(b.surveyDate ?? '')).slice(0, 5);

  return (
    <div className="p-6 overflow-y-auto h-full bg-white space-y-6">
      {/* Stats */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard icon={<Users className="text-violet-600" size={20} />} label="Open Leads" value={String(stats.totalLeads)} color="violet" />
        <StatCard icon={<Briefcase className="text-orange-600" size={20} />} label="Active Jobs" value={String(stats.activeJobs)} color="blue" />
        <StatCard icon={<TrendingUp className="text-orange-600" size={20} />} label="Pipeline Value" value={formatCurrency(stats.pipeline)} color="indigo" />
        <StatCard icon={<PoundSterling className="text-green-600" size={20} />} label="Revenue Paid" value={formatCurrency(stats.revenue)} color="green" />
        <StatCard icon={<Trophy className="text-amber-600" size={20} />} label="Jobs Won" value={String(stats.won)} color="amber" />
        <StatCard icon={<CheckCircle2 className="text-emerald-600" size={20} />} label="Completed" value={String(stats.completed)} color="emerald" />
        <StatCard icon={<Star className="text-pink-600" size={20} />} label="Conversion" value={`${stats.convRate}%`} color="pink" />
        <StatCard icon={<Clock className="text-gray-500" size={20} />} label="Total Leads" value={String(leads.length)} color="gray" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Recent activity */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          <div className="px-5 py-4 border-b border-gray-100">
            <h2 className="font-bold text-gray-800">Recent Activity</h2>
          </div>
          <div className="divide-y divide-gray-50">
            {recentLeads.map(lead => (
              <div key={lead.id} className="flex items-center gap-3 px-5 py-3 hover:bg-gray-50">
                <div className="w-8 h-8 rounded-full bg-orange-100 flex items-center justify-center text-orange-700 font-bold text-sm shrink-0">
                  {lead.name[0]}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold text-gray-800 truncate">{lead.name}</p>
                  <p className="text-xs text-gray-400 truncate">{lead.jobType} · {lead.address.split(',')[1]?.trim()}</p>
                </div>
                <div className="text-right shrink-0">
                  <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${jobTypeColor(lead.jobType)}`}>{lead.stage}</span>
                  <p className="text-xs text-gray-400 mt-0.5">{formatDate(lead.updatedAt)}</p>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Upcoming surveys */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          <div className="px-5 py-4 border-b border-gray-100">
            <h2 className="font-bold text-gray-800">Upcoming Surveys</h2>
          </div>
          {upcomingSurveys.length > 0 ? (
            <div className="divide-y divide-gray-50">
              {upcomingSurveys.map(lead => (
                <div key={lead.id} className="flex items-center gap-3 px-5 py-3 hover:bg-gray-50">
                  <div className="w-10 h-10 rounded-xl bg-orange-50 flex flex-col items-center justify-center text-orange-700 shrink-0">
                    <span className="text-xs font-bold leading-none">{lead.surveyDate?.split('-')[2]}</span>
                    <span className="text-xs leading-none opacity-70">{new Date(lead.surveyDate!).toLocaleDateString('en-GB', { month: 'short' })}</span>
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-gray-800 truncate">{lead.name}</p>
                    <p className="text-xs text-gray-400">{lead.jobType} · {lead.surveyTime}</p>
                  </div>
                  <span className="text-xs text-orange-600 font-medium shrink-0">{lead.address.split(',').slice(-2).join(',').trim()}</span>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm text-gray-400 text-center py-8">No surveys booked</p>
          )}
        </div>
      </div>

      {/* Job locations map */}
      <JobsMap />

      {/* Pipeline breakdown */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
        <h2 className="font-bold text-gray-800 mb-4">Pipeline Breakdown</h2>
        <div className="space-y-3">
          {(['New Lead','Survey Booked','Quote Sent','Won','In Progress','Completed','Paid'] as const).map(stage => {
            const count = leads.filter(l => l.stage === stage).length;
            const val = leads.filter(l => l.stage === stage).reduce((s, l) => s + l.value, 0);
            const pct = leads.length ? Math.round(count / leads.length * 100) : 0;
            return (
              <div key={stage} className="flex items-center gap-4">
                <span className="text-sm text-gray-600 w-32 shrink-0">{stage}</span>
                <div className="flex-1 bg-gray-100 rounded-full h-2">
                  <div className="h-2 rounded-full bg-orange-500 transition-all" style={{ width: `${pct}%` }} />
                </div>
                <span className="text-sm font-bold text-gray-700 w-6 text-right">{count}</span>
                {val > 0 && <span className="text-xs text-gray-400 w-20 text-right">{formatCurrency(val)}</span>}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

function StatCard({ icon, label, value, color }: { icon: React.ReactNode; label: string; value: string; color: string }) {
  const bg: Record<string, string> = {
    violet: 'bg-violet-50', blue: 'bg-orange-50', indigo: 'bg-orange-50', green: 'bg-green-50',
    amber: 'bg-amber-50', emerald: 'bg-emerald-50', pink: 'bg-pink-50', gray: 'bg-gray-50',
  };
  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 flex items-center gap-3">
      <div className={`w-10 h-10 rounded-xl ${bg[color] ?? 'bg-gray-50'} flex items-center justify-center shrink-0`}>
        {icon}
      </div>
      <div>
        <p className="text-xs text-gray-500 font-medium">{label}</p>
        <p className="text-lg font-bold text-gray-800 leading-tight">{value}</p>
      </div>
    </div>
  );
}

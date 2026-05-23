import { TrendingUp, Briefcase, PoundSterling, CheckCircle2, Clock, Trophy, Users, Star, AlertTriangle, CalendarClock, Hammer, BadgePoundSterling, Bell } from 'lucide-react';
import { useStore } from '../store/useStore';
import { formatCurrency, formatDate, jobTypeColor } from '../utils/helpers';
import JobsMap from '../components/Map/JobsMap';
import LeadDetailPanel from '../components/LeadDetail/LeadDetailPanel';

export default function DashboardPage() {
  const { leads, setSelectedId, setCurrentPage, selectedId } = useStore();

  const today = new Date().toISOString().split('T')[0];
  const tomorrow = new Date(Date.now() + 86400000).toISOString().split('T')[0];

  const stats = {
    totalLeads: leads.filter(l => ['New Lead', 'Survey Booked', 'Quote Sent'].includes(l.stage)).length,
    activeJobs: leads.filter(l => l.stage === 'In Progress').length,
    revenue: leads.filter(l => l.stage === 'Paid').reduce((s, l) => s + l.value, 0),
    pipeline: leads.filter(l => ['Won', 'In Progress', 'Completed'].includes(l.stage)).reduce((s, l) => s + l.value, 0),
    won: leads.filter(l => l.stage === 'Won').length,
    completed: leads.filter(l => l.stage === 'Completed').length,
    convRate: leads.length ? Math.round(leads.filter(l => ['Won','In Progress','Completed','Paid'].includes(l.stage)).length / leads.length * 100) : 0,
  };

  // Automations
  const surveysToday       = leads.filter(l => l.surveyDate === today);
  const surveysTomorrow    = leads.filter(l => l.surveyDate === tomorrow);
  const jobsStartingToday  = leads.filter(l => l.startDate === today);
  const jobsStartingTmrw   = leads.filter(l => l.startDate === tomorrow);
  const jobsEndingToday    = leads.filter(l => l.endDate === today);
  const overduePayments    = leads.filter(l => {
    if (l.stage !== 'Completed') return false;
    if (!l.completedDate) return false;
    const days = Math.floor((Date.now() - new Date(l.completedDate).getTime()) / 86400000);
    return days >= 7;
  });
  const unpaidDeposits = leads.filter(l =>
    ['Won', 'In Progress'].includes(l.stage) && !l.depositPaid && l.deposit > 0
  );

  const automations = [
    ...surveysToday.map(l => ({ lead: l, label: `Survey TODAY${l.surveyTime ? ` at ${l.surveyTime}` : ''}`, color: 'bg-violet-50 border-violet-200 text-violet-700', icon: <CalendarClock size={14} /> })),
    ...surveysTomorrow.map(l => ({ lead: l, label: `Survey tomorrow${l.surveyTime ? ` at ${l.surveyTime}` : ''}`, color: 'bg-violet-50 border-violet-100 text-violet-600', icon: <CalendarClock size={14} /> })),
    ...jobsStartingToday.map(l => ({ lead: l, label: 'Job starts TODAY', color: 'bg-green-50 border-green-200 text-green-700', icon: <Hammer size={14} /> })),
    ...jobsStartingTmrw.map(l => ({ lead: l, label: 'Job starts tomorrow', color: 'bg-green-50 border-green-100 text-green-600', icon: <Hammer size={14} /> })),
    ...jobsEndingToday.map(l => ({ lead: l, label: 'Job ends TODAY', color: 'bg-orange-50 border-orange-200 text-orange-700', icon: <Hammer size={14} /> })),
    ...overduePayments.map(l => ({ lead: l, label: `Payment overdue — completed ${formatDate(l.completedDate)}`, color: 'bg-red-50 border-red-200 text-red-700', icon: <AlertTriangle size={14} /> })),
    ...unpaidDeposits.map(l => ({ lead: l, label: `Deposit not received — ${formatCurrency(l.deposit)}`, color: 'bg-amber-50 border-amber-200 text-amber-700', icon: <BadgePoundSterling size={14} /> })),
  ];

  const recentLeads = [...leads].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)).slice(0, 8);
  const upcomingSurveys = leads.filter(l => l.surveyDate && l.surveyDate >= today).sort((a, b) => (a.surveyDate ?? '').localeCompare(b.surveyDate ?? '')).slice(0, 5);

  return (
    <>
    <div className="p-4 sm:p-5 lg:p-6 overflow-y-auto h-full bg-white space-y-4 lg:space-y-6">

      {/* Automations / Action Required */}
      {automations.length > 0 && (
        <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
          <div className="flex items-center gap-2 px-5 py-3 border-b border-gray-100">
            <Bell size={16} className="text-orange-500" />
            <h2 className="font-bold text-gray-800 text-sm">Action Required</h2>
            <span className="ml-auto bg-orange-600 text-white text-xs font-bold w-5 h-5 rounded-full flex items-center justify-center">{automations.length}</span>
          </div>
          <div className="divide-y divide-gray-50">
            {automations.map(({ lead, label, color, icon }, i) => (
              <button key={i} onClick={() => setSelectedId(lead.id)}
                className={`w-full flex items-center gap-3 px-5 py-3 hover:bg-gray-50 text-left transition-colors`}>
                <div className={`flex items-center justify-center w-8 h-8 rounded-lg border ${color} shrink-0`}>
                  {icon}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold text-gray-800 truncate">{lead.name}</p>
                  <p className={`text-xs font-medium ${color.split(' ').find(c => c.startsWith('text-'))}`}>{label}</p>
                </div>
                <span className={`text-xs font-medium px-2 py-0.5 rounded-full shrink-0 ${jobTypeColor(lead.jobType)}`}>{lead.jobType}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Stats */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 lg:gap-4">
        <StatCard icon={<Users className="text-violet-600" size={20} />} label="Open Leads" value={String(stats.totalLeads)} color="violet" />
        <StatCard icon={<Briefcase className="text-orange-600" size={20} />} label="Active Jobs" value={String(stats.activeJobs)} color="orange" />
        <StatCard icon={<TrendingUp className="text-orange-600" size={20} />} label="Pipeline Value" value={formatCurrency(stats.pipeline)} color="orange" />
        <StatCard icon={<PoundSterling className="text-green-600" size={20} />} label="Revenue Paid" value={formatCurrency(stats.revenue)} color="green" />
        <StatCard icon={<Trophy className="text-amber-600" size={20} />} label="Jobs Won" value={String(stats.won)} color="amber" />
        <StatCard icon={<CheckCircle2 className="text-emerald-600" size={20} />} label="Completed" value={String(stats.completed)} color="emerald" />
        <StatCard icon={<Star className="text-pink-600" size={20} />} label="Conversion" value={`${stats.convRate}%`} color="pink" />
        <StatCard icon={<Clock className="text-gray-500" size={20} />} label="Total Leads" value={String(leads.length)} color="gray" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 lg:gap-6">
        {/* Recent activity */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          <div className="px-5 py-4 border-b border-gray-100">
            <h2 className="font-bold text-gray-800">Recent Activity</h2>
          </div>
          <div className="divide-y divide-gray-50">
            {recentLeads.map(lead => (
              <div key={lead.id} className="flex items-center gap-3 px-5 py-3 hover:bg-gray-50 cursor-pointer" onClick={() => setSelectedId(lead.id)}>
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
          <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
            <h2 className="font-bold text-gray-800">Upcoming Surveys</h2>
            <button onClick={() => setCurrentPage('calendar')} className="text-xs text-orange-600 hover:text-orange-800 font-medium">View calendar →</button>
          </div>
          {upcomingSurveys.length > 0 ? (
            <div className="divide-y divide-gray-50">
              {upcomingSurveys.map(lead => (
                <div key={lead.id} className="flex items-center gap-3 px-5 py-3 hover:bg-gray-50 cursor-pointer" onClick={() => setSelectedId(lead.id)}>
                  <div className={`w-10 h-10 rounded-xl flex flex-col items-center justify-center shrink-0 ${lead.surveyDate === today ? 'bg-orange-600 text-white' : 'bg-orange-50 text-orange-700'}`}>
                    <span className="text-xs font-bold leading-none">{lead.surveyDate?.split('-')[2]}</span>
                    <span className="text-xs leading-none opacity-70">{new Date(lead.surveyDate! + 'T12:00:00').toLocaleDateString('en-GB', { month: 'short' })}</span>
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-gray-800 truncate">{lead.name}</p>
                    <p className="text-xs text-gray-400">{lead.jobType}{lead.surveyTime ? ` · ${lead.surveyTime}` : ''}</p>
                  </div>
                  {lead.surveyDate === today && <span className="text-xs font-bold text-orange-600 shrink-0">TODAY</span>}
                  {lead.surveyDate === tomorrow && <span className="text-xs font-bold text-amber-600 shrink-0">TOMORROW</span>}
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

    {selectedId && <LeadDetailPanel />}
    </>
  );
}

function StatCard({ icon, label, value, color }: { icon: React.ReactNode; label: string; value: string; color: string }) {
  const bg: Record<string, string> = {
    violet: 'bg-violet-50', orange: 'bg-orange-50', green: 'bg-green-50',
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

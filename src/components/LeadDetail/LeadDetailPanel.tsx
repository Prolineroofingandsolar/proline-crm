import { useState } from 'react';
import { X, Phone, MessageSquare, Mail, Trophy, Play, CheckCircle, CreditCard, ChevronRight, Trash2, Calendar, Star } from 'lucide-react';
import { useStore } from '../../store/useStore';
import { formatCurrency, jobTypeColor } from '../../utils/helpers';
import TasksTab from './TasksTab';
import PhotosTab from './PhotosTab';
import MaterialsTab from './MaterialsTab';
import NotesTab from './NotesTab';
import FilesTab from './FilesTab';
import InfoTab from './InfoTab';
import ReviewRequestModal from '../Reviews/ReviewRequestModal';

const TABS = ['Tasks', 'Photos', 'Materials', 'Notes', 'Files', 'Info'] as const;
type Tab = typeof TABS[number];

const stageColors: Record<string, string> = {
  'New Lead': 'bg-violet-100 text-violet-700',
  'Survey Booked': 'bg-sky-100 text-sky-700',
  'Quote Sent': 'bg-amber-100 text-amber-700',
  'Won': 'bg-green-100 text-green-700',
  'In Progress': 'bg-orange-100 text-orange-700',
  'Completed': 'bg-emerald-100 text-emerald-700',
  'Paid': 'bg-teal-100 text-teal-700',
};

export default function LeadDetailPanel() {
  const { leads, selectedId, setSelectedId, moveToStage, markAsWon, deleteLead, updateLead } = useStore();
  const [activeTab, setActiveTab] = useState<Tab>('Tasks');
  const [showReviewModal, setShowReviewModal] = useState(false);

  const lead = leads.find(l => l.id === selectedId);
  if (!lead) return null;

  const close = () => setSelectedId(null);

  const handleMarkPaid = () => {
    moveToStage(lead.id, 'Paid');
    if (!lead.reviewRequestSent) setShowReviewModal(true);
  };

  return (
    <>
      {/* Backdrop */}
      <div className="fixed inset-0 z-40 bg-black/20" onClick={close} />

      {/* Panel — full width, 92dvh on mobile (leaves room for top bar) / capped on desktop */}
      <div className="fixed bottom-0 left-0 right-0 z-50 bg-white rounded-t-2xl shadow-2xl flex flex-col"
        style={{ height: 'min(92dvh, 720px)' }}>

        {/* Header */}
        <div className="flex items-start justify-between px-4 py-3 border-b border-gray-100 shrink-0 gap-2">
          <div className="flex items-start gap-2 min-w-0">
            <button onClick={close} className="p-1 rounded-lg hover:bg-gray-100 text-gray-500 mt-0.5 shrink-0">
              <X size={18} />
            </button>
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-1.5">
                <h2 className="font-bold text-gray-800 text-base">{lead.name}</h2>
                <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${stageColors[lead.stage] ?? 'bg-gray-100 text-gray-600'}`}>
                  {lead.stage}
                </span>
                <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${jobTypeColor(lead.jobType)}`}>
                  {lead.jobType}
                </span>
              </div>
              <p className="text-xs text-gray-400 truncate">{lead.jobRef} · {lead.address}</p>
            </div>
          </div>

          {/* Action buttons — icon-only on mobile, labelled on desktop */}
          <div className="flex items-center gap-1.5 shrink-0">
            <a href={`tel:${lead.phone}`}
              className="p-2 rounded-lg bg-gray-50 border border-gray-200 text-gray-600 hover:bg-gray-100">
              <Phone size={15} />
            </a>
            <a href={`https://wa.me/${lead.phone.replace(/\D/g,'')}`} target="_blank" rel="noreferrer"
              className="p-2 rounded-lg bg-green-50 border border-green-200 text-green-700 hover:bg-green-100">
              <MessageSquare size={15} />
            </a>
            <a href={`mailto:${lead.email}`}
              className="p-2 rounded-lg bg-orange-50 border border-orange-200 text-orange-700 hover:bg-orange-100">
              <Mail size={15} />
            </a>
            <button onClick={() => { deleteLead(lead.id); close(); }}
              className="p-2 rounded-lg hover:bg-red-50 text-gray-400 hover:text-red-500">
              <Trash2 size={15} />
            </button>
          </div>
        </div>

        {/* Review request button for paid jobs */}
        {lead.stage === 'Paid' && (
          <div className="px-4 py-2 border-b border-gray-100 shrink-0">
            <button onClick={() => setShowReviewModal(true)}
              className={`w-full flex items-center justify-center gap-1.5 text-sm px-4 py-2 rounded-xl font-medium transition-colors ${
                lead.reviewRequestSent
                  ? 'bg-gray-100 text-gray-500 hover:bg-gray-200'
                  : 'bg-yellow-500 hover:bg-yellow-600 text-white'
              }`}>
              <Star size={15} />
              {lead.reviewRequestSent ? 'Review Request Sent — Send Again' : 'Send Review Request'}
            </button>
          </div>
        )}

        {/* Stage advance — full-width banner on mobile */}
        {lead.stage !== 'Paid' && (
          <div className="px-4 py-2 border-b border-gray-100 shrink-0">
            {lead.stage === 'New Lead' && (
              <button onClick={() => moveToStage(lead.id, 'Survey Booked')}
                className="w-full flex items-center justify-center gap-1.5 text-sm bg-orange-600 text-white hover:bg-orange-700 px-4 py-2 rounded-xl font-medium transition-colors">
                <ChevronRight size={15} /> Book Survey
              </button>
            )}
            {lead.stage === 'Survey Booked' && (
              <button onClick={() => moveToStage(lead.id, 'Quote Sent')}
                className="w-full flex items-center justify-center gap-1.5 text-sm bg-amber-600 text-white hover:bg-amber-700 px-4 py-2 rounded-xl font-medium transition-colors">
                <ChevronRight size={15} /> Send Quote
              </button>
            )}
            {lead.stage === 'Quote Sent' && (
              <button onClick={() => markAsWon(lead.id)}
                className="w-full flex items-center justify-center gap-1.5 text-sm bg-green-600 text-white hover:bg-green-700 px-4 py-2 rounded-xl font-semibold transition-colors">
                <Trophy size={15} /> Mark as Won
              </button>
            )}
            {lead.stage === 'Won' && (
              <button onClick={() => moveToStage(lead.id, 'In Progress')}
                className="w-full flex items-center justify-center gap-1.5 text-sm bg-orange-600 text-white hover:bg-orange-700 px-4 py-2 rounded-xl font-medium transition-colors">
                <Play size={15} /> Start Job
              </button>
            )}
            {lead.stage === 'In Progress' && (
              <button onClick={() => moveToStage(lead.id, 'Completed')}
                className="w-full flex items-center justify-center gap-1.5 text-sm bg-emerald-600 text-white hover:bg-emerald-700 px-4 py-2 rounded-xl font-medium transition-colors">
                <CheckCircle size={15} /> Mark Complete
              </button>
            )}
            {lead.stage === 'Completed' && (
              <button onClick={handleMarkPaid}
                className="w-full flex items-center justify-center gap-1.5 text-sm bg-teal-600 text-white hover:bg-teal-700 px-4 py-2 rounded-xl font-medium transition-colors">
                <CreditCard size={15} /> Mark Paid
              </button>
            )}
          </div>
        )}

        {/* Body: stacked on mobile, side-by-side on md+ */}
        <div className="flex flex-col md:flex-row flex-1 overflow-hidden">
          {/* Key info — horizontal scroll strip on mobile, sidebar on desktop */}
          <div className="md:w-52 md:shrink-0 md:border-r md:border-gray-100 md:p-4 md:space-y-3 md:overflow-y-auto
                          flex md:flex-col gap-4 overflow-x-auto scrollbar-hide px-4 py-2 border-b md:border-b-0 border-gray-100 shrink-0">
            {[
              { label: 'Phone', value: lead.phone },
              { label: 'Email', value: lead.email },
              { label: 'Value', value: formatCurrency(lead.value), bold: true },
              { label: 'Deposit', value: `${formatCurrency(lead.deposit)}${lead.depositPaid ? ' ✓' : ''}` },
              { label: 'Balance', value: formatCurrency(lead.balance), bold: true },
            ].map(({ label, value, bold }) => value ? (
              <div key={label} className="shrink-0">
                <p className="text-[10px] text-gray-400 font-semibold uppercase tracking-wide whitespace-nowrap">{label}</p>
                <p className={`${bold ? 'font-bold text-gray-800' : 'text-gray-700'} text-sm whitespace-nowrap`}>{value}</p>
              </div>
            ) : null)}

            {/* Start / End dates — always visible for all stages */}
            {true && (
              <>
                <div className="shrink-0 min-w-[130px] md:min-w-0">
                  <p className="text-[10px] text-gray-400 font-semibold uppercase tracking-wide mb-1 flex items-center gap-1">
                    <Calendar size={10} /> Start Date
                  </p>
                  <input
                    type="date"
                    value={lead.startDate ?? ''}
                    onChange={e => updateLead(lead.id, { startDate: e.target.value || undefined })}
                    className="w-full border border-gray-200 rounded-lg px-2 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-orange-400 text-gray-700"
                  />
                </div>
                <div className="shrink-0 min-w-[130px] md:min-w-0">
                  <p className="text-[10px] text-gray-400 font-semibold uppercase tracking-wide mb-1 flex items-center gap-1">
                    <Calendar size={10} /> End Date
                  </p>
                  <input
                    type="date"
                    value={lead.endDate ?? ''}
                    onChange={e => updateLead(lead.id, { endDate: e.target.value || undefined })}
                    className="w-full border border-gray-200 rounded-lg px-2 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-orange-400 text-gray-700"
                  />
                </div>
              </>
            )}

            {lead.stage === 'In Progress' && (
              <div className="shrink-0 min-w-[120px] md:min-w-0">
                <div className="flex justify-between text-xs mb-1">
                  <span className="text-gray-500">Progress</span>
                  <span className="font-bold text-orange-600">{lead.progress}%</span>
                </div>
                <div className="w-full bg-gray-100 rounded-full h-2">
                  <div className="h-2 rounded-full bg-orange-500 transition-all" style={{ width: `${lead.progress}%` }} />
                </div>
              </div>
            )}
          </div>

          {/* Tabs */}
          <div className="flex-1 flex flex-col overflow-hidden">
            <div className="flex border-b border-gray-100 px-4 shrink-0 overflow-x-auto scrollbar-hide">
              {TABS.map(tab => (
                <button key={tab} onClick={() => setActiveTab(tab)}
                  className={`px-3 py-2.5 text-sm font-medium whitespace-nowrap border-b-2 transition-colors ${
                    activeTab === tab
                      ? 'border-orange-600 text-orange-600'
                      : 'border-transparent text-gray-500 hover:text-gray-700'
                  }`}>
                  {tab}
                </button>
              ))}
            </div>
            <div className="flex-1 overflow-y-auto pb-safe">
              {activeTab === 'Tasks'     && <TasksTab lead={lead} />}
              {activeTab === 'Photos'    && <PhotosTab lead={lead} />}
              {activeTab === 'Materials' && <MaterialsTab lead={lead} />}
              {activeTab === 'Notes'     && <NotesTab lead={lead} />}
              {activeTab === 'Files'     && <FilesTab lead={lead} />}
              {activeTab === 'Info'      && <InfoTab lead={lead} />}
            </div>
          </div>
        </div>
      </div>

      {showReviewModal && (
        <ReviewRequestModal
          lead={lead}
          onClose={() => setShowReviewModal(false)}
          onMarkSent={() => updateLead(lead.id, { reviewRequestSent: true })}
        />
      )}
    </>
  );
}

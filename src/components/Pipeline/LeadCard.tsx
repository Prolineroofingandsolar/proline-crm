import { Phone, Calendar, ChevronRight, Trophy, Play, CheckCircle, CreditCard, Clock, MessageSquare, Mail, GripVertical } from 'lucide-react';
import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import type { Lead } from '../../types';
import { formatCurrency, formatDateShort, dayLabel, jobTypeColor } from '../../utils/helpers';
import { useStore } from '../../store/useStore';

interface Props {
  lead: Lead;
  onClick: () => void;
  isDragging?: boolean;
}

export default function LeadCard({ lead, onClick, isDragging = false }: Props) {
  const { moveToStage, markAsWon } = useStore();

  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging: sortableDragging,
  } = useSortable({ id: lead.id, data: { stage: lead.stage } });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: sortableDragging ? 0.4 : 1,
    zIndex: sortableDragging ? 999 : undefined,
  };

  const stopProp = (fn: () => void) => (e: React.MouseEvent) => { e.stopPropagation(); fn(); };

  return (
    <div
      ref={setNodeRef}
      style={style}
      onClick={onClick}
      className={`bg-white rounded-xl shadow-sm border border-gray-100 p-3 cursor-pointer hover:shadow-md hover:border-orange-200 transition-all select-none ${isDragging ? 'shadow-2xl rotate-1 border-orange-300' : ''}`}
    >
      {/* Drag handle + name row */}
      <div className="flex items-start gap-1.5 mb-1.5">
        <button
          {...attributes}
          {...listeners}
          onClick={e => e.stopPropagation()}
          className="mt-0.5 shrink-0 text-gray-300 hover:text-gray-400 cursor-grab active:cursor-grabbing touch-none p-0.5 rounded"
        >
          <GripVertical size={14} />
        </button>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-1">
            <div className="min-w-0">
              <p className="font-semibold text-gray-800 text-sm leading-tight truncate">{lead.name}</p>
              <span className={`text-xs px-1.5 py-0.5 rounded-md font-medium mt-0.5 inline-block ${jobTypeColor(lead.jobType)}`}>
                {lead.jobType}
              </span>
            </div>
            {lead.stage === 'New Lead' && (
              <a href={`tel:${lead.phone}`} onClick={e => e.stopPropagation()}
                className="p-1.5 rounded-full bg-orange-50 text-orange-600 hover:bg-orange-100 shrink-0">
                <Phone size={13} />
              </a>
            )}
          </div>
        </div>
      </div>

      {/* Location */}
      <p className="text-xs text-gray-500 mb-2 pl-6">{lead.address.split(',').slice(-2).join(',').trim()}</p>

      {/* Stage-specific content */}
      <div className="pl-6">
        {lead.stage === 'New Lead' && (
          <div className="flex items-center justify-between">
            <span className={`text-xs font-medium ${dayLabel(lead.createdAt) === 'Today' ? 'text-green-600' : dayLabel(lead.createdAt) === 'Yesterday' ? 'text-amber-600' : 'text-gray-400'}`}>
              {dayLabel(lead.createdAt)}
            </span>
            <div className="flex gap-1">
              <a href={`https://wa.me/${lead.phone.replace(/\s/g, '')}`} onClick={e => e.stopPropagation()} target="_blank" rel="noreferrer"
                className="p-1 rounded bg-green-50 text-green-600 hover:bg-green-100"><MessageSquare size={12} /></a>
              <a href={`mailto:${lead.email}`} onClick={e => e.stopPropagation()}
                className="p-1 rounded bg-orange-50 text-orange-600 hover:bg-orange-100"><Mail size={12} /></a>
            </div>
          </div>
        )}

        {lead.stage === 'Survey Booked' && lead.surveyDate && (
          <div className="flex items-center gap-1.5 text-xs text-gray-600">
            <Calendar size={12} className="text-orange-400 shrink-0" />
            <span>{formatDateShort(lead.surveyDate)}{lead.surveyTime ? `, ${lead.surveyTime}` : ''}</span>
          </div>
        )}

        {lead.stage === 'Quote Sent' && (
          <div className="space-y-1">
            {lead.value > 0 && <p className="text-sm font-bold text-gray-800">{formatCurrency(lead.value)}</p>}
            {lead.updatedAt && (
              <div className="flex items-center gap-1 text-xs text-amber-600">
                <Clock size={11} />
                <span>Follow up: {formatDateShort(lead.updatedAt)}</span>
              </div>
            )}
          </div>
        )}

        {lead.stage === 'Won' && (
          <div className="space-y-1">
            <p className="text-sm font-bold text-gray-800">{formatCurrency(lead.value)}</p>
            <span className="text-xs font-medium text-green-600 bg-green-50 px-2 py-0.5 rounded-full">
              Won {dayLabel(lead.wonDate ?? lead.updatedAt).toLowerCase()}
            </span>
          </div>
        )}

        {lead.stage === 'In Progress' && (
          <div className="space-y-1">
            <div className="flex items-center justify-between text-xs text-gray-500">
              <span>Start: {formatDateShort(lead.startDate)}</span>
              <span className="font-semibold text-orange-600">{lead.progress}%</span>
            </div>
            <div className="w-full bg-gray-100 rounded-full h-1.5">
              <div className="h-1.5 rounded-full bg-orange-500 transition-all" style={{ width: `${lead.progress}%` }} />
            </div>
          </div>
        )}

        {lead.stage === 'Completed' && (
          <div className="flex items-center justify-between">
            <p className="text-sm font-bold text-gray-800">{formatCurrency(lead.value)}</p>
            {lead.photos.length > 0 ? (
              <img src={lead.photos[lead.photos.length - 1].url} className="w-10 h-10 rounded-lg object-cover" alt="job" />
            ) : (
              <span className="text-xs text-green-600 font-medium">Done {formatDateShort(lead.completedDate)}</span>
            )}
          </div>
        )}

        {lead.stage === 'Paid' && (
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-bold text-gray-800">{formatCurrency(lead.value)}</p>
              <p className="text-xs text-gray-400">Paid {formatDateShort(lead.paidDate)}</p>
            </div>
            <span className="bg-green-100 text-green-700 text-xs font-semibold px-2 py-0.5 rounded-full flex items-center gap-1">
              <CreditCard size={11} /> Paid
            </span>
          </div>
        )}

        {/* Action buttons */}
        <div className="mt-2 flex gap-1.5" onClick={e => e.stopPropagation()}>
          {lead.stage === 'New Lead' && (
            <button onClick={stopProp(() => moveToStage(lead.id, 'Survey Booked'))}
              className="flex-1 flex items-center justify-center gap-1 text-xs bg-orange-50 text-orange-700 hover:bg-orange-100 py-1 rounded-lg font-medium transition-colors">
              <Calendar size={11} /> Book Survey
            </button>
          )}
          {lead.stage === 'Survey Booked' && (
            <button onClick={stopProp(() => moveToStage(lead.id, 'Quote Sent'))}
              className="flex-1 flex items-center justify-center gap-1 text-xs bg-amber-50 text-amber-700 hover:bg-amber-100 py-1 rounded-lg font-medium transition-colors">
              <ChevronRight size={11} /> Send Quote
            </button>
          )}
          {lead.stage === 'Quote Sent' && (
            <button onClick={stopProp(() => markAsWon(lead.id))}
              className="flex-1 flex items-center justify-center gap-1 text-xs bg-green-600 text-white hover:bg-green-700 py-1 rounded-lg font-medium transition-colors">
              <Trophy size={11} /> Mark as Won
            </button>
          )}
          {lead.stage === 'Won' && (
            <button onClick={stopProp(() => moveToStage(lead.id, 'In Progress'))}
              className="flex-1 flex items-center justify-center gap-1 text-xs bg-orange-600 text-white hover:bg-orange-700 py-1 rounded-lg font-medium transition-colors">
              <Play size={11} /> Start Job
            </button>
          )}
          {lead.stage === 'In Progress' && (
            <button onClick={stopProp(() => moveToStage(lead.id, 'Completed'))}
              className="flex-1 flex items-center justify-center gap-1 text-xs bg-emerald-600 text-white hover:bg-emerald-700 py-1 rounded-lg font-medium transition-colors">
              <CheckCircle size={11} /> Mark Complete
            </button>
          )}
          {lead.stage === 'Completed' && (
            <button onClick={stopProp(() => moveToStage(lead.id, 'Paid'))}
              className="flex-1 flex items-center justify-center gap-1 text-xs bg-green-600 text-white hover:bg-green-700 py-1 rounded-lg font-medium transition-colors">
              <CreditCard size={11} /> Mark Paid
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

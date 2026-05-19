import { Plus } from 'lucide-react';
import { useDroppable } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import type { Lead, Stage } from '../../types';
import { formatCurrency } from '../../utils/helpers';
import { useStore } from '../../store/useStore';
import LeadCard from './LeadCard';

const stageConfig: Record<Stage, { header: string; dot: string; bg: string; dropBg: string }> = {
  'New Lead':      { header: 'bg-violet-500',  dot: 'bg-violet-400', bg: 'bg-violet-50',  dropBg: 'bg-violet-100' },
  'Survey Booked': { header: 'bg-sky-500',       dot: 'bg-sky-400',    bg: 'bg-sky-50',     dropBg: 'bg-sky-100' },
  'Quote Sent':    { header: 'bg-amber-500',    dot: 'bg-amber-400',  bg: 'bg-amber-50',   dropBg: 'bg-amber-100' },
  'Won':           { header: 'bg-green-500',    dot: 'bg-green-400',  bg: 'bg-green-50',   dropBg: 'bg-green-100' },
  'In Progress':   { header: 'bg-orange-600',   dot: 'bg-orange-400', bg: 'bg-orange-50',  dropBg: 'bg-orange-100' },
  'Completed':     { header: 'bg-emerald-600',  dot: 'bg-emerald-400',bg: 'bg-emerald-50', dropBg: 'bg-emerald-100' },
  'Paid':          { header: 'bg-teal-600',     dot: 'bg-teal-400',   bg: 'bg-teal-50',    dropBg: 'bg-teal-100' },
};

interface Props {
  stage: Stage;
  leads: Lead[];
  onCardClick: (id: string) => void;
  onAddLead?: () => void;
}

export default function StageColumn({ stage, leads, onCardClick, onAddLead }: Props) {
  const { users, currentUserId } = useStore();
  const isAdmin = users.find(u => u.id === currentUserId)?.role === 'admin';
  const cfg = stageConfig[stage];
  const total = leads.reduce((s, l) => s + l.value, 0);

  const { setNodeRef, isOver } = useDroppable({ id: stage });

  return (
    <div className="flex flex-col w-56 shrink-0 rounded-xl overflow-hidden shadow-sm border border-gray-100">
      {/* Header */}
      <div className={`${cfg.header} px-3 py-2.5 flex items-center justify-between`}>
        <div className="flex items-center gap-2">
          <span className={`w-2 h-2 rounded-full ${cfg.dot} opacity-80`} />
          <span className="text-white font-semibold text-sm">{stage}</span>
        </div>
        <span className="bg-white/30 text-white text-xs font-bold w-5 h-5 rounded-full flex items-center justify-center">
          {leads.length}
        </span>
      </div>

      {/* Value summary */}
      {isAdmin && total > 0 && (
        <div className="bg-white border-b border-gray-100 px-3 py-1.5 text-xs text-gray-500 font-medium">
          Total: <span className="text-gray-700 font-bold">{formatCurrency(total)}</span>
        </div>
      )}

      {/* Drop zone + cards */}
      <div
        ref={setNodeRef}
        className={`flex-1 overflow-y-auto p-2 space-y-2 min-h-24 transition-colors ${isOver ? cfg.dropBg : cfg.bg}`}
      >
        <SortableContext items={leads.map(l => l.id)} strategy={verticalListSortingStrategy}>
          {leads.map(lead => (
            <LeadCard key={lead.id} lead={lead} onClick={() => onCardClick(lead.id)} />
          ))}
        </SortableContext>

        {leads.length === 0 && (
          <div className={`flex items-center justify-center h-16 rounded-xl border-2 border-dashed transition-colors ${
            isOver ? 'border-orange-400 bg-orange-50' : 'border-gray-200'
          }`}>
            <p className={`text-xs font-medium ${isOver ? 'text-orange-500' : 'text-gray-300'}`}>
              {isOver ? 'Drop here' : 'No items'}
            </p>
          </div>
        )}
      </div>

      {/* Add button */}
      {(stage === 'New Lead' || stage === 'Survey Booked') && (
        <button
          onClick={onAddLead}
          className="bg-white border-t border-gray-100 hover:bg-gray-50 flex items-center justify-center gap-1 py-2 text-xs text-gray-500 hover:text-orange-600 transition-colors"
        >
          <Plus size={13} /> Add Lead
        </button>
      )}
    </div>
  );
}

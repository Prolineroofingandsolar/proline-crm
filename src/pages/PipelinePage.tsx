import { useState } from 'react';
import {
  DndContext,
  DragOverlay,
  PointerSensor,
  TouchSensor,
  useSensor,
  useSensors,
  closestCorners,
} from '@dnd-kit/core';
import type { DragStartEvent, DragEndEvent } from '@dnd-kit/core';
import type { Stage } from '../types';
import { STAGES } from '../data/mockData';
import { useStore } from '../store/useStore';
import StageColumn from '../components/Pipeline/StageColumn';
import LeadCard from '../components/Pipeline/LeadCard';
import AddLeadModal from '../components/Pipeline/AddLeadModal';
import LeadDetailPanel from '../components/LeadDetail/LeadDetailPanel';
import { formatCurrency } from '../utils/helpers';

const WORKFLOWS: Record<string, Stage[]> = {
  Sales: ['New Lead', 'Survey Booked', 'Quote Preparing', 'Quote Sent'],
  Jobs: ['Won', 'Scheduled', 'In Progress', 'Waiting for Payment'],
  Archive: ['Completed', 'Paid', 'Lost'],
};

export default function PipelinePage() {
  const { leads, selectedId, setSelectedId, searchQuery, moveToStage, users, currentUserId, simpleMode } = useStore();
  const canMove = users.find(user => user.id === currentUserId)?.role === 'admin' && !simpleMode;
  const [showAddModal, setShowAddModal] = useState(false);
  const [addStage, setAddStage] = useState<Stage>('New Lead');
  const [activeId, setActiveId] = useState<string | null>(null);
  const [mobileStage, setMobileStage] = useState<Stage>('New Lead');
  const [workflow, setWorkflow] = useState('Sales');
  const visibleStages = WORKFLOWS[workflow];
  const [mode, setMode] = useState<'Board' | 'List'>('Board');
  const [showFilters, setShowFilters] = useState(false);
  const [source, setSource] = useState('');
  const [thisMonth, setThisMonth] = useState(false);
  const [minimum, setMinimum] = useState('');

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(TouchSensor,   { activationConstraint: { delay: 200, tolerance: 6 } })
  );

  const searched = searchQuery
    ? leads.filter(l =>
        l.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        l.jobType.toLowerCase().includes(searchQuery.toLowerCase()) ||
        l.address.toLowerCase().includes(searchQuery.toLowerCase()) ||
        l.phone.includes(searchQuery) ||
        l.jobRef.toLowerCase().includes(searchQuery.toLowerCase())
      )
    : leads;
  const currentMonth = new Date().toLocaleDateString('en-CA').slice(0, 7);
  const filtered = searched.filter(lead => (!source || lead.source === source)
    && (!thisMonth || lead.createdAt.startsWith(currentMonth))
    && (!minimum || lead.value >= Number(minimum)));
  const sources = Array.from(new Set(leads.map(lead => lead.source).filter(Boolean))).sort();
  const scopedLeads = filtered.filter(lead => visibleStages.includes(lead.stage));

  const activeLead = activeId ? leads.find(l => l.id === activeId) : null;

  const handleDragStart = (event: DragStartEvent) => {
    setActiveId(String(event.active.id));
  };

  const handleDragOver = () => {
    // We resolve the final stage in dragEnd for simplicity
  };

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    setActiveId(null);

    if (!over || !canMove) return;

    const draggedId = String(active.id);
    const draggedLead = leads.find(l => l.id === draggedId);
    if (!draggedLead) return;

    // "over" can be a stage column (droppable id = stage name)
    // or another card (sortable id = card id → look up its stage)
    let targetStage: Stage;

    const overIdStr = String(over.id);
    if ((STAGES as readonly string[]).includes(overIdStr)) {
      targetStage = overIdStr as Stage;
    } else {
      const overLead = leads.find(l => l.id === overIdStr);
      if (!overLead) return;
      targetStage = overLead.stage;
    }

    if (draggedLead.stage !== targetStage) {
      moveToStage(draggedId, targetStage);
    }
  };

  const handleAddForStage = (stage: Stage) => {
    setAddStage(stage);
    setShowAddModal(true);
  };

  return (
    <div className="flex flex-col h-full overflow-hidden bg-white">
      {searchQuery && (
        <div className="px-4 pt-3 pb-0">
          <p className="text-sm text-gray-500">
            Showing <span className="font-semibold text-gray-800">{filtered.length}</span> results for "
            <span className="text-orange-600">{searchQuery}</span>"
          </p>
        </div>
      )}

      <div className="flex gap-1 mx-4 mt-4 p-1 rounded-lg bg-gray-100 self-start" aria-label="Pipeline workflow">
        {Object.keys(WORKFLOWS).map(name => <button key={name} onClick={() => { setWorkflow(name); setMobileStage(WORKFLOWS[name][0]); }} aria-pressed={workflow === name} className={`px-4 py-2 rounded-md text-sm font-semibold ${workflow === name ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-900'}`}>{name}</button>)}
      </div>
      <div className="flex flex-wrap items-center gap-2 px-4 pt-3 text-sm">
        <div className="flex rounded-lg bg-gray-100 p-1" aria-label="Pipeline view">
          {(['Board', 'List'] as const).map(item => <button key={item} onClick={() => setMode(item)} aria-pressed={mode === item} className={`rounded-md px-3 py-1.5 font-medium ${mode === item ? 'bg-white shadow-sm' : 'text-gray-500'}`}>{item}</button>)}
        </div>
        <button onClick={() => setShowFilters(!showFilters)} aria-expanded={showFilters} className="rounded-lg border border-gray-200 px-3 py-2 font-medium text-gray-700">Filters</button>
        {showFilters && <div className="flex flex-wrap gap-2 items-center">
          <select aria-label="Source" value={source} onChange={event => setSource(event.target.value)} className="rounded-lg border border-gray-200 p-2"><option value="">All sources</option>{sources.map(item => <option key={item}>{item}</option>)}</select>
          <select aria-label="Period" value={thisMonth ? 'month' : 'all'} onChange={event => setThisMonth(event.target.value === 'month')} className="rounded-lg border border-gray-200 p-2"><option value="all">All time</option><option value="month">This month</option></select>
          {canMove && <input aria-label="Minimum value" type="number" min="0" placeholder="Minimum value (£)" value={minimum} onChange={event => setMinimum(event.target.value)} className="w-40 rounded-lg border border-gray-200 p-2" />}
          <button onClick={() => { setSource(''); setThisMonth(false); setMinimum(''); }} className="text-orange-700">Clear filters</button>
        </div>}
      </div>
      {mode === 'List' ? <div className="flex-1 overflow-auto p-4"><div className="divide-y rounded-xl border border-gray-200 bg-white">{scopedLeads.map(lead => <button key={lead.id} onClick={() => setSelectedId(lead.id)} className="flex w-full items-center gap-3 p-4 text-left hover:bg-gray-50"><span className="min-w-0 flex-1"><span className="block font-semibold text-gray-900">{lead.name}</span><span className="block truncate text-sm text-gray-500">{lead.jobRef} · {lead.jobType} · {lead.address}</span></span><span className="text-sm text-gray-600">{lead.stage}</span>{canMove && <span className="hidden text-sm font-semibold sm:block">{formatCurrency(lead.value)}</span>}</button>)}{scopedLeads.length === 0 && <p className="p-6 text-center text-sm text-gray-500">No matching work in this workflow.</p>}</div></div> : <DndContext
        sensors={sensors}
        collisionDetection={closestCorners}
        onDragStart={handleDragStart}
        onDragOver={handleDragOver}
        onDragEnd={handleDragEnd}
      >
        {/* On phones show one stage at a time; the full board remains available on wider screens. */}
        <div className="sm:hidden flex flex-1 min-h-0 flex-col gap-3 p-3">
          <div className="flex gap-2 overflow-x-auto pb-1" aria-label="Pipeline stages">
            {visibleStages.map(stage => <button key={stage} onClick={() => setMobileStage(stage as Stage)} aria-pressed={mobileStage === stage} className={`shrink-0 rounded-xl px-3 py-2 text-sm font-semibold ${mobileStage === stage ? 'bg-orange-600 text-white' : 'bg-gray-100 text-gray-700'}`}>{stage} <span className="ml-1 opacity-75">{filtered.filter(lead => lead.stage === stage).length}</span></button>)}
          </div>
          <div className="flex-1 min-h-0"><StageColumn stage={mobileStage} leads={filtered.filter(lead => lead.stage === mobileStage)} onCardClick={setSelectedId} onAddLead={() => handleAddForStage(mobileStage)} fullWidth /></div>
        </div>
        <div className="hidden sm:block flex-1 overflow-x-auto overflow-y-hidden p-4">
          <div className="flex gap-3 h-full" style={{ minWidth: 'max-content' }}>
            {visibleStages.map(stage => (
              <StageColumn
                key={stage}
                stage={stage as Stage}
                leads={filtered.filter(l => l.stage === stage)}
                onCardClick={(id) => setSelectedId(id)}
                onAddLead={() => handleAddForStage(stage as Stage)}
              />
            ))}
          </div>
        </div>

        {/* Drag overlay — ghost card that follows the cursor */}
        <DragOverlay dropAnimation={{ duration: 150, easing: 'ease' }}>
          {activeLead ? (
            <div className="rotate-2 scale-105 shadow-2xl">
              <LeadCard lead={activeLead} onClick={() => {}} isDragging />
            </div>
          ) : null}
        </DragOverlay>
      </DndContext>}

      {/* Detail panel */}
      {selectedId && <LeadDetailPanel />}

      {/* Add lead modal */}
      {showAddModal && <AddLeadModal defaultStage={addStage} onClose={() => setShowAddModal(false)} />}
    </div>
  );
}

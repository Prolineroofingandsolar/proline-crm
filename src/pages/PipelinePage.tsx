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
import type { DragStartEvent, DragOverEvent, DragEndEvent } from '@dnd-kit/core';
import type { Stage } from '../types';
import { STAGES } from '../data/mockData';
import { useStore } from '../store/useStore';
import StageColumn from '../components/Pipeline/StageColumn';
import LeadCard from '../components/Pipeline/LeadCard';
import AddLeadModal from '../components/Pipeline/AddLeadModal';
import LeadDetailPanel from '../components/LeadDetail/LeadDetailPanel';

export default function PipelinePage() {
  const { leads, selectedId, setSelectedId, searchQuery, moveToStage } = useStore();
  const [showAddModal, setShowAddModal] = useState(false);
  const [addStage, setAddStage] = useState<Stage>('New Lead');
  const [activeId, setActiveId] = useState<string | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(TouchSensor,   { activationConstraint: { delay: 200, tolerance: 6 } })
  );

  const filtered = searchQuery
    ? leads.filter(l =>
        l.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        l.jobType.toLowerCase().includes(searchQuery.toLowerCase()) ||
        l.address.toLowerCase().includes(searchQuery.toLowerCase()) ||
        l.phone.includes(searchQuery) ||
        l.jobRef.toLowerCase().includes(searchQuery.toLowerCase())
      )
    : leads;

  const activeLead = activeId ? leads.find(l => l.id === activeId) : null;

  const handleDragStart = (event: DragStartEvent) => {
    setActiveId(String(event.active.id));
  };

  const handleDragOver = (_event: DragOverEvent) => {
    // We resolve the final stage in dragEnd for simplicity
  };

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    setActiveId(null);

    if (!over) return;

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

      <DndContext
        sensors={sensors}
        collisionDetection={closestCorners}
        onDragStart={handleDragStart}
        onDragOver={handleDragOver}
        onDragEnd={handleDragEnd}
      >
        {/* Board */}
        <div className="flex-1 overflow-x-auto overflow-y-hidden p-4">
          <div className="flex gap-3 h-full" style={{ minWidth: 'max-content' }}>
            {STAGES.map(stage => (
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
      </DndContext>

      {/* Detail panel */}
      {selectedId && <LeadDetailPanel />}

      {/* Add lead modal */}
      {showAddModal && <AddLeadModal defaultStage={addStage} onClose={() => setShowAddModal(false)} />}
    </div>
  );
}

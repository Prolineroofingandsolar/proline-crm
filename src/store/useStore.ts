import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import type { Lead, Stage, Material, FileItem, Photo, Contact } from '../types';
import { initialLeads } from '../data/mockData';
import { generateId } from '../utils/helpers';

const DEFAULT_TASKS = [
  'Order materials', 'Scaffold booked', 'Confirm start date with customer',
  'Deposit received', 'Before photos', 'Remove old roof', 'Install new roof',
  'Snagging / Quality check', 'After photos', 'Send invoice & request review',
];

export interface GeneralTask {
  id: string;
  title: string;
  completed: boolean;
  completedDate?: string;
  dueDate?: string;
  priority: 'low' | 'medium' | 'high';
  category: string;
  notes?: string;
  createdAt: string;
}

interface Store {
  leads: Lead[];
  contacts: Contact[];
  generalTasks: GeneralTask[];
  apiKey: string;
  selectedId: string | null;
  currentPage: string;
  searchQuery: string;
  toast: { message: string; type: 'success' | 'info' | 'error' } | null;

  setCurrentPage: (page: string) => void;
  setSelectedId: (id: string | null) => void;
  setSearchQuery: (q: string) => void;
  setApiKey: (key: string) => void;
  showToast: (message: string, type?: 'success' | 'info' | 'error') => void;

  upsertContact: (data: Pick<Contact, 'name' | 'phone' | 'email' | 'address'>) => void;
  deleteContact: (id: string) => void;

  addLead: (data: Omit<Lead, 'id' | 'jobRef' | 'createdAt' | 'updatedAt' | 'tasks' | 'photos' | 'notes' | 'files' | 'materials'>) => void;
  updateLead: (id: string, updates: Partial<Lead>) => void;
  deleteLead: (id: string) => void;
  moveToStage: (id: string, stage: Stage) => void;
  markAsWon: (id: string) => void;

  toggleTask: (leadId: string, taskId: string) => void;
  addTask: (leadId: string, title: string) => void;
  deleteTask: (leadId: string, taskId: string) => void;

  addGeneralTask: (data: Omit<GeneralTask, 'id' | 'createdAt' | 'completed'>) => void;
  toggleGeneralTask: (id: string) => void;
  deleteGeneralTask: (id: string) => void;
  updateGeneralTask: (id: string, updates: Partial<GeneralTask>) => void;

  addNote: (leadId: string, content: string) => void;
  deleteNote: (leadId: string, noteId: string) => void;

  addMaterial: (leadId: string, mat: Omit<Material, 'id'>) => void;
  updateMaterial: (leadId: string, matId: string, updates: Partial<Material>) => void;
  deleteMaterial: (leadId: string, matId: string) => void;

  addFile: (leadId: string, file: Omit<FileItem, 'id'>) => void;
  deleteFile: (leadId: string, fileId: string) => void;

  addPhoto: (leadId: string, photo: Omit<Photo, 'id'>) => void;
  deletePhoto: (leadId: string, photoId: string) => void;
}

const jobCounter = { n: 21 };

export const useStore = create<Store>()(
  persist(
    (set, get) => ({
      leads: initialLeads,
      // Seed contacts from unique customers in initialLeads (deduped by phone)
      contacts: Object.values(
        initialLeads.reduce((acc, l) => {
          if (!acc[l.phone]) acc[l.phone] = { id: l.id + '_c', name: l.name, phone: l.phone, email: l.email, address: l.address, createdAt: l.createdAt };
          return acc;
        }, {} as Record<string, Contact>)
      ),
      generalTasks: [
        { id: 'gt1', title: 'MOT reminder – work van', completed: false, priority: 'high', category: 'Vehicle', dueDate: '2024-06-15', createdAt: '2024-05-01' },
        { id: 'gt2', title: 'Renew public liability insurance', completed: false, priority: 'high', category: 'Admin', dueDate: '2024-07-01', createdAt: '2024-05-01' },
        { id: 'gt3', title: 'Order more leaflets for letterboxing', completed: false, priority: 'low', category: 'Marketing', createdAt: '2024-05-10' },
        { id: 'gt4', title: 'Chase accountant re: year-end accounts', completed: true, completedDate: '2024-05-12', priority: 'medium', category: 'Finance', createdAt: '2024-05-05' },
      ],
      apiKey: '',
      selectedId: null,
      currentPage: 'pipeline',
      searchQuery: '',
      toast: null,

      setCurrentPage: (page) => set({ currentPage: page, selectedId: null }),
      setSelectedId: (id) => set({ selectedId: id }),
      setSearchQuery: (searchQuery) => set({ searchQuery }),
      setApiKey: (apiKey) => set({ apiKey }),
      showToast: (message, type = 'success') => {
        set({ toast: { message, type } });
        setTimeout(() => set({ toast: null }), 3000);
      },

      upsertContact: ({ name, phone, email, address }) => {
        const now = new Date().toISOString().split('T')[0];
        set(s => {
          const existing = s.contacts.find(c => c.phone === phone);
          if (existing) {
            return { contacts: s.contacts.map(c => c.phone === phone ? { ...c, name, email, address } : c) };
          }
          return { contacts: [{ id: generateId(), name, phone, email, address, createdAt: now }, ...s.contacts] };
        });
      },

      deleteContact: (id) => set(s => ({ contacts: s.contacts.filter(c => c.id !== id) })),

      addLead: (data) => {
        const ref = `JOB-${String(jobCounter.n++).padStart(3, '0')}`;
        const now = new Date().toISOString().split('T')[0];
        const lead: Lead = {
          ...data,
          id: generateId(),
          jobRef: ref,
          createdAt: now,
          updatedAt: now,
          tasks: [],
          photos: [],
          notes: [],
          files: [],
          materials: [],
        };
        set(s => ({ leads: [lead, ...s.leads] }));
        get().upsertContact({ name: data.name, phone: data.phone, email: data.email, address: data.address });
        get().showToast(`New lead added: ${data.name}`);
      },

      updateLead: (id, updates) =>
        set(s => ({
          leads: s.leads.map(l => l.id === id ? { ...l, ...updates, updatedAt: new Date().toISOString().split('T')[0] } : l),
        })),

      deleteLead: (id) => {
        set(s => ({ leads: s.leads.filter(l => l.id !== id), selectedId: s.selectedId === id ? null : s.selectedId }));
        get().showToast('Lead deleted', 'info');
      },

      moveToStage: (id, stage) => {
        const lead = get().leads.find(l => l.id === id);
        if (!lead) return;
        const now = new Date().toISOString().split('T')[0];
        const updates: Partial<Lead> = { stage, updatedAt: now };
        if (stage === 'Won') updates.wonDate = now;
        if (stage === 'In Progress') {
          updates.startDate = updates.startDate ?? now;
          if (lead.tasks.length === 0) {
            updates.tasks = DEFAULT_TASKS.map((title, i) => ({ id: `${id}_t${i}`, title, completed: false }));
          }
        }
        if (stage === 'Completed') updates.completedDate = now;
        if (stage === 'Paid') { updates.paidDate = now; updates.balance = 0; }
        set(s => ({ leads: s.leads.map(l => l.id === id ? { ...l, ...updates } : l) }));
        get().showToast(`Moved to ${stage}`);
      },

      markAsWon: (id) => {
        get().moveToStage(id, 'Won');
        get().showToast('🎉 Job Won! Card moved to Won column', 'success');
      },

      toggleTask: (leadId, taskId) =>
        set(s => ({
          leads: s.leads.map(l => {
            if (l.id !== leadId) return l;
            const now = new Date().toISOString().split('T')[0];
            const tasks = l.tasks.map(t =>
              t.id === taskId ? { ...t, completed: !t.completed, completedDate: !t.completed ? now : undefined } : t
            );
            const done = tasks.filter(t => t.completed).length;
            const progress = tasks.length ? Math.round((done / tasks.length) * 100) : 0;
            return { ...l, tasks, progress };
          }),
        })),

      addTask: (leadId, title) =>
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId
              ? { ...l, tasks: [...l.tasks, { id: generateId(), title, completed: false }] }
              : l
          ),
        })),

      deleteTask: (leadId, taskId) =>
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, tasks: l.tasks.filter(t => t.id !== taskId) } : l
          ),
        })),

      addGeneralTask: (data) => {
        const now = new Date().toISOString().split('T')[0];
        set(s => ({
          generalTasks: [{ ...data, id: generateId(), completed: false, createdAt: now }, ...s.generalTasks],
        }));
      },

      toggleGeneralTask: (id) =>
        set(s => ({
          generalTasks: s.generalTasks.map(t => {
            if (t.id !== id) return t;
            const now = new Date().toISOString().split('T')[0];
            return { ...t, completed: !t.completed, completedDate: !t.completed ? now : undefined };
          }),
        })),

      deleteGeneralTask: (id) =>
        set(s => ({ generalTasks: s.generalTasks.filter(t => t.id !== id) })),

      updateGeneralTask: (id, updates) =>
        set(s => ({ generalTasks: s.generalTasks.map(t => t.id === id ? { ...t, ...updates } : t) })),

      addNote: (leadId, content) => {
        const now = new Date().toISOString().split('T')[0];
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId
              ? { ...l, notes: [{ id: generateId(), content, date: now, author: 'Harman' }, ...l.notes] }
              : l
          ),
        }));
      },

      deleteNote: (leadId, noteId) =>
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, notes: l.notes.filter(n => n.id !== noteId) } : l
          ),
        })),

      addMaterial: (leadId, mat) =>
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, materials: [...l.materials, { ...mat, id: generateId() }] } : l
          ),
        })),

      updateMaterial: (leadId, matId, updates) =>
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId
              ? { ...l, materials: l.materials.map(m => m.id === matId ? { ...m, ...updates } : m) }
              : l
          ),
        })),

      deleteMaterial: (leadId, matId) =>
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, materials: l.materials.filter(m => m.id !== matId) } : l
          ),
        })),

      addFile: (leadId, file) =>
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, files: [...l.files, { ...file, id: generateId() }] } : l
          ),
        })),

      deleteFile: (leadId, fileId) =>
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, files: l.files.filter(f => f.id !== fileId) } : l
          ),
        })),

      addPhoto: (leadId, photo) =>
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, photos: [...l.photos, { ...photo, id: generateId() }] } : l
          ),
        })),

      deletePhoto: (leadId, photoId) =>
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, photos: l.photos.filter(p => p.id !== photoId) } : l
          ),
        })),
    }),
    { name: 'proline-crm-storage' }
  )
);

import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import type { Lead, Stage, Material, FileItem, Photo, Contact, AppUser, GeneralTask, TimesheetEntry } from '../types';
import { generateId } from '../utils/helpers';
import { hashPassword } from '../utils/crypto';
import { subscribeToPush } from '../utils/push';
import {
  supabase,
  leadToDb, dbToLead,
  userToDb, dbToUser,
  contactToDb, dbToContact,
  generalTaskToDb, dbToGeneralTask,
  timesheetEntryToDb, dbToTimesheetEntry,
} from '../lib/supabase';

const STAGE_TASKS: Partial<Record<Stage, string[]>> = {
  'New Lead': [
    'Call customer to discuss requirements',
    'Confirm contact details',
    'Check job location / access',
  ],
  'Survey Booked': [
    'Confirm survey appointment with customer',
    'Prepare survey checklist',
    'Review job requirements before visit',
  ],
  'Quote Sent': [
    'Follow up on quote within 3 days',
    'Answer any customer questions',
    'Chase quote if no response after 7 days',
  ],
  'Won': [
    'Collect deposit',
    'Confirm start date with customer',
    'Order materials',
    'Brief the team on job details',
  ],
  'In Progress': [
    'Confirm materials delivered',
    'Daily progress check',
    'Take before & during photos',
    'Keep customer updated',
  ],
  'Completed': [
    'Final inspection with customer',
    'Take completion photos',
    'Send final invoice',
    'Collect outstanding balance',
  ],
  'Paid': [
    'File all job paperwork',
    'Request customer review / referral',
    'Update job records',
  ],
};

// Re-export for components that imported GeneralTask from here
export type { GeneralTask };

interface Store {
  isLoaded: boolean;
  loadData: () => Promise<void>;

  users: AppUser[];
  currentUserId: string | null;
  leads: Lead[];
  contacts: Contact[];
  generalTasks: GeneralTask[];
  timesheetEntries: TimesheetEntry[];
  apiKey: string;
  selectedId: string | null;
  currentPage: string;
  searchQuery: string;
  toast: { message: string; type: 'success' | 'info' | 'error' } | null;

  login: (username: string, password: string) => Promise<boolean>;
  logout: () => void;
  addUser: (name: string, username: string, password: string, role: 'admin' | 'user') => Promise<{ ok: boolean; error?: string }>;
  deleteUser: (id: string) => void;
  changePassword: (id: string, newPassword: string) => Promise<void>;
  updateUserName: (id: string, name: string) => void;
  updateUserProfile: (id: string, updates: Partial<Pick<AppUser, 'dayRate' | 'cisRate' | 'utrNumber' | 'bankName' | 'bankAccountNumber' | 'bankSortCode'>>) => void;

  pushEnabled: boolean;
  enablePushNotifications: () => Promise<void>;

  addTimesheetEntry: (data: Omit<TimesheetEntry, 'id' | 'createdAt'>) => void;
  upsertTimesheetEntry: (data: Omit<TimesheetEntry, 'id' | 'createdAt'>) => void;
  deleteTimesheetEntry: (id: string) => void;

  setCurrentPage: (page: string) => void;
  setSelectedId: (id: string | null) => void;
  setSearchQuery: (q: string) => void;
  setApiKey: (key: string) => void;
  showToast: (message: string, type?: 'success' | 'info' | 'error') => void;

  upsertContact: (data: Pick<Contact, 'name' | 'phone' | 'email' | 'address'>) => void;
  deleteContact: (id: string) => void;

  geocodeLeads: (ids: string[]) => Promise<void>;

  addLead: (data: Omit<Lead, 'id' | 'jobRef' | 'createdAt' | 'updatedAt' | 'tasks' | 'photos' | 'notes' | 'files' | 'materials'>) => void;
  updateLead: (id: string, updates: Partial<Lead>) => void;
  deleteLead: (id: string) => void;
  moveToStage: (id: string, stage: Stage) => void;
  markAsWon: (id: string) => void;

  toggleTask: (leadId: string, taskId: string) => void;
  addTask: (leadId: string, title: string, isTemplate?: boolean) => void;
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

let jobCounterN = 1;

export const useStore = create<Store>()(
  persist(
    (set, get) => {
      // Sync the current state of a lead to Supabase after a local update.
      // Uses update (not upsert) so stale local data can never silently insert a duplicate.
      const syncLead = (leadId: string) => {
        const lead = get().leads.find(l => l.id === leadId);
        if (!lead) return;
        supabase.from('leads').update(leadToDb(lead)).eq('id', leadId)
          .then(({ error }) => {
            if (error) {
              console.error('Lead sync error:', error);
              get().showToast('Save failed — check your connection', 'error');
            }
          });
      };

      return {
      isLoaded: false,
      users: [],
      currentUserId: null,
      leads: [],
      contacts: [],
      generalTasks: [],
      timesheetEntries: [],
      apiKey: '',
      pushEnabled: false,
      selectedId: null,
      currentPage: 'pipeline',
      searchQuery: '',
      toast: null,

      // ── Load all data from Supabase ─────────────────────────────────────────
      loadData: async () => {
        const [leadsRes, usersRes, contactsRes, tasksRes, timesheetRes] = await Promise.all([
          supabase.from('leads').select('*').order('updated_at', { ascending: false }),
          supabase.from('app_users').select('*'),
          supabase.from('contacts').select('*').order('created_at', { ascending: false }),
          supabase.from('general_tasks').select('*').order('created_at', { ascending: false }),
          supabase.from('timesheet_entries').select('*').order('date', { ascending: false }),
        ]);

        const leads = (leadsRes.data ?? []).map(r => dbToLead(r as Record<string, unknown>));
        const users = (usersRes.data ?? []).map(r => dbToUser(r as Record<string, unknown>));
        const contacts = (contactsRes.data ?? []).map(r => dbToContact(r as Record<string, unknown>));
        const generalTasks = (tasksRes.data ?? []).map(r => dbToGeneralTask(r as Record<string, unknown>));
        const timesheetEntries = (timesheetRes.data ?? []).map(r => dbToTimesheetEntry(r as Record<string, unknown>));

        // Set job counter to 1 above the highest existing job number
        const maxNum = leads.reduce((max, l) => {
          const m = l.jobRef.match(/JOB-(\d+)/);
          return m ? Math.max(max, parseInt(m[1])) : max;
        }, 0);
        jobCounterN = maxNum + 1;

        // Backfill contacts for any existing lead that doesn't have one yet
        const now = new Date().toISOString().split('T')[0];
        const existingPhones = new Set(contacts.map(c => c.phone));
        const missingContacts: Contact[] = [];
        for (const lead of leads) {
          if (!lead.phone || existingPhones.has(lead.phone)) continue;
          existingPhones.add(lead.phone);
          missingContacts.push({ id: generateId(), name: lead.name, phone: lead.phone, email: lead.email, address: lead.address, createdAt: now });
        }
        if (missingContacts.length > 0) {
          supabase.from('contacts').insert(missingContacts.map(contactToDb)).then(({ error }) => {
            if (error) console.error('Contact backfill error:', error);
          });
        }
        const allContacts = [...contacts, ...missingContacts];

        set({ leads, users, contacts: allContacts, generalTasks, timesheetEntries, isLoaded: true });
      },

      // ── Auth ────────────────────────────────────────────────────────────────
      login: async (username, password) => {
        const hash = await hashPassword(password);
        const user = get().users.find(
          u => u.username.toLowerCase() === username.toLowerCase() && u.passwordHash === hash
        );
        if (user) { set({ currentUserId: user.id }); return true; }
        return false;
      },

      logout: () => set({ currentUserId: null }),

      addUser: async (name, username, password, role) => {
        const existing = get().users.find(u => u.username.toLowerCase() === username.toLowerCase());
        if (existing) return { ok: false, error: 'Username already taken' };
        const hash = await hashPassword(password);
        const now = new Date().toISOString().split('T')[0];
        const user: AppUser = { id: generateId(), name, username, passwordHash: hash, role, createdAt: now };
        set(s => ({ users: [...s.users, user] }));
        supabase.from('app_users').insert(userToDb(user)).then(({ error }) => {
          if (error) console.error('addUser sync error:', error);
        });
        return { ok: true };
      },

      deleteUser: (id) => {
        set(s => ({ users: s.users.filter(u => u.id !== id) }));
        supabase.from('app_users').delete().eq('id', id);
      },

      changePassword: async (id, newPassword) => {
        const hash = await hashPassword(newPassword);
        set(s => ({ users: s.users.map(u => u.id === id ? { ...u, passwordHash: hash } : u) }));
        supabase.from('app_users').update({ password_hash: hash }).eq('id', id);
      },

      updateUserName: (id, name) => {
        set(s => ({ users: s.users.map(u => u.id === id ? { ...u, name } : u) }));
        supabase.from('app_users').update({ name }).eq('id', id);
      },

      updateUserProfile: (id, updates) => {
        set(s => ({ users: s.users.map(u => u.id === id ? { ...u, ...updates } : u) }));
        const dbUpdates: Record<string, unknown> = {};
        if (updates.dayRate !== undefined) dbUpdates.day_rate = updates.dayRate;
        if (updates.cisRate !== undefined) dbUpdates.cis_rate = updates.cisRate;
        if (updates.utrNumber !== undefined) dbUpdates.utr_number = updates.utrNumber;
        if (updates.bankName !== undefined) dbUpdates.bank_name = updates.bankName;
        if (updates.bankAccountNumber !== undefined) dbUpdates.bank_account_number = updates.bankAccountNumber;
        if (updates.bankSortCode !== undefined) dbUpdates.bank_sort_code = updates.bankSortCode;
        supabase.from('app_users').update(dbUpdates).eq('id', id);
      },

      upsertTimesheetEntry: (data) => {
        const now = new Date().toISOString().split('T')[0];
        const existing = get().timesheetEntries.find(e => e.userId === data.userId && e.date === data.date);
        if (existing) {
          const updated: TimesheetEntry = { ...existing, ...data };
          set(s => ({ timesheetEntries: s.timesheetEntries.map(e => e.id === existing.id ? updated : e) }));
          supabase.from('timesheet_entries').update(timesheetEntryToDb(updated)).eq('id', existing.id)
            .then(({ error }) => {
              if (error) {
                console.error('timesheet update error:', error);
                get().showToast('Save failed — check your connection', 'error');
              }
            });
        } else {
          const entry: TimesheetEntry = { ...data, id: generateId(), createdAt: now };
          set(s => ({ timesheetEntries: [entry, ...s.timesheetEntries] }));
          supabase.from('timesheet_entries').insert(timesheetEntryToDb(entry))
            .then(({ error }) => {
              if (error) {
                console.error('timesheet insert error:', error);
                get().showToast('Save failed — check your connection', 'error');
              }
            });
        }
      },

      addTimesheetEntry: (data) => {
        const now = new Date().toISOString().split('T')[0];
        const entry: TimesheetEntry = { ...data, id: generateId(), createdAt: now };
        set(s => ({ timesheetEntries: [entry, ...s.timesheetEntries] }));
        supabase.from('timesheet_entries').insert(timesheetEntryToDb(entry))
          .then(({ error }) => { if (error) console.error('timesheet insert error:', error); });
      },

      deleteTimesheetEntry: (id) => {
        set(s => ({ timesheetEntries: s.timesheetEntries.filter(e => e.id !== id) }));
        supabase.from('timesheet_entries').delete().eq('id', id);
      },

      enablePushNotifications: async () => {
        const subscription = await subscribeToPush();
        if (!subscription) {
          if ('Notification' in window && Notification.permission === 'denied') {
            get().showToast('Notifications blocked — allow in device Settings', 'error');
          }
          return;
        }
        const now = new Date().toISOString().split('T')[0];
        const { error } = await supabase.from('push_subscriptions').upsert(
          {
            id: generateId(),
            user_id: get().currentUserId ?? '',
            endpoint: subscription.endpoint,
            subscription: subscription.toJSON(),
            created_at: now,
          },
          { onConflict: 'endpoint' }
        );
        if (error) {
          console.error('push subscription save error:', error);
          get().showToast('Failed to save notification subscription', 'error');
          return;
        }
        set({ pushEnabled: true });
        get().showToast('Push notifications enabled');
      },

      // ── UI ──────────────────────────────────────────────────────────────────
      setCurrentPage: (page) => set({ currentPage: page, selectedId: null }),
      setSelectedId: (id) => set({ selectedId: id }),
      setSearchQuery: (searchQuery) => set({ searchQuery }),
      setApiKey: (apiKey) => set({ apiKey }),
      showToast: (message, type = 'success') => {
        set({ toast: { message, type } });
        setTimeout(() => set({ toast: null }), 3000);
      },

      // ── Contacts ────────────────────────────────────────────────────────────
      upsertContact: ({ name, phone, email, address }) => {
        const now = new Date().toISOString().split('T')[0];
        const existing = get().contacts.find(c => c.phone === phone);
        if (existing) {
          const updated: Contact = { ...existing, name, email, address };
          set(s => ({ contacts: s.contacts.map(c => c.phone === phone ? updated : c) }));
          supabase.from('contacts').upsert(contactToDb(updated)).then(({ error }) => {
            if (error) console.error('upsertContact sync error:', error);
          });
        } else {
          const contact: Contact = { id: generateId(), name, phone, email, address, createdAt: now };
          set(s => ({ contacts: [contact, ...s.contacts] }));
          supabase.from('contacts').insert(contactToDb(contact)).then(({ error }) => {
            if (error) console.error('upsertContact insert error:', error);
          });
        }
      },

      deleteContact: (id) => {
        set(s => ({ contacts: s.contacts.filter(c => c.id !== id) }));
        supabase.from('contacts').delete().eq('id', id);
      },

      // ── Geocode ─────────────────────────────────────────────────────────────
      geocodeLeads: async (ids) => {
        const toGeocode = get().leads.filter(l => ids.includes(l.id) && !l.lat && l.address);
        for (const lead of toGeocode) {
          try {
            const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(lead.address)}&format=json&limit=1&countrycodes=gb`;
            const res = await fetch(url, { headers: { 'Accept-Language': 'en', 'User-Agent': 'ProLineCRM/1.0' } });
            const data = await res.json();
            if (data[0]) {
              const lat = parseFloat(data[0].lat);
              const lng = parseFloat(data[0].lon);
              set(s => ({ leads: s.leads.map(l => l.id === lead.id ? { ...l, lat, lng } : l) }));
              await supabase.from('leads').update({ lat, lng }).eq('id', lead.id);
            }
          } catch { /* silently skip */ }
          await new Promise(r => setTimeout(r, 1100));
        }
      },

      // ── Leads ───────────────────────────────────────────────────────────────
      addLead: (data) => {
        const ref = `JOB-${String(jobCounterN++).padStart(3, '0')}`;
        const now = new Date().toISOString().split('T')[0];
        const lead: Lead = {
          ...data, id: generateId(), jobRef: ref, createdAt: now, updatedAt: now,
          tasks: [], photos: [], notes: [], files: [], materials: [],
        };
        set(s => ({ leads: [lead, ...s.leads] }));
        supabase.from('leads').insert(leadToDb(lead)).then(({ error }) => {
          if (error) {
            console.error('addLead sync error:', error);
            get().showToast('Lead saved locally but failed to sync — check connection', 'error');
          }
        });
        get().upsertContact({ name: data.name, phone: data.phone, email: data.email, address: data.address });
        get().showToast(`New lead added: ${data.name}`);
        supabase.functions.invoke('send-push', {
          body: { title: 'New Lead Added', body: `${data.name} — ${data.jobType ?? 'Job'}` },
        });
      },

      updateLead: (id, updates) => {
        const updatedAt = new Date().toISOString().split('T')[0];
        set(s => ({
          leads: s.leads.map(l => l.id === id ? { ...l, ...updates, updatedAt } : l),
        }));
        syncLead(id);
      },

      deleteLead: (id) => {
        set(s => ({ leads: s.leads.filter(l => l.id !== id), selectedId: s.selectedId === id ? null : s.selectedId }));
        supabase.from('leads').delete().eq('id', id);
        get().showToast('Lead deleted', 'info');
      },

      moveToStage: (id, stage) => {
        const lead = get().leads.find(l => l.id === id);
        if (!lead) return;
        const now = new Date().toISOString().split('T')[0];
        const updates: Partial<Lead> = { stage, updatedAt: now };
        if (stage === 'Won') updates.wonDate = now;
        if (stage === 'In Progress' && !lead.startDate) updates.startDate = now;
        if (stage === 'Completed') updates.completedDate = now;
        if (stage === 'Paid') { updates.paidDate = now; updates.balance = 0; }
        const customTasks = lead.tasks.filter(t => !t.isTemplate);
        const newTemplateTasks = (STAGE_TASKS[stage] ?? []).map(title => ({
          id: generateId(), title, completed: false, isTemplate: true as const,
        }));
        updates.tasks = [...newTemplateTasks, ...customTasks];
        set(s => ({ leads: s.leads.map(l => l.id === id ? { ...l, ...updates } : l) }));
        syncLead(id);
        get().showToast(`Moved to ${stage}`);
        const pushTitles: Partial<Record<Stage, string>> = {
          Won: 'Job Won',
          Completed: 'Job Completed',
          Paid: 'Payment Received',
        };
        const pushTitle = pushTitles[stage];
        if (pushTitle) {
          supabase.functions.invoke('send-push', {
            body: { title: pushTitle, body: `${lead.name} — ${lead.jobRef}` },
          });
        }
      },

      markAsWon: (id) => {
        get().moveToStage(id, 'Won');
        get().showToast('🎉 Job Won! Card moved to Won column', 'success');
      },

      // ── Lead tasks ──────────────────────────────────────────────────────────
      toggleTask: (leadId, taskId) => {
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
        }));
        syncLead(leadId);
      },

      addTask: (leadId, title, isTemplate = false) => {
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, tasks: [...l.tasks, { id: generateId(), title, completed: false, isTemplate }] } : l
          ),
        }));
        syncLead(leadId);
      },

      deleteTask: (leadId, taskId) => {
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, tasks: l.tasks.filter(t => t.id !== taskId) } : l
          ),
        }));
        syncLead(leadId);
      },

      // ── General tasks ────────────────────────────────────────────────────────
      addGeneralTask: (data) => {
        const now = new Date().toISOString().split('T')[0];
        const task: GeneralTask = { ...data, id: generateId(), completed: false, createdAt: now };
        set(s => ({ generalTasks: [task, ...s.generalTasks] }));
        supabase.from('general_tasks').insert(generalTaskToDb(task));
      },

      toggleGeneralTask: (id) => {
        set(s => ({
          generalTasks: s.generalTasks.map(t => {
            if (t.id !== id) return t;
            const now = new Date().toISOString().split('T')[0];
            return { ...t, completed: !t.completed, completedDate: !t.completed ? now : undefined };
          }),
        }));
        const task = get().generalTasks.find(t => t.id === id);
        if (task) supabase.from('general_tasks').upsert(generalTaskToDb(task));
      },

      deleteGeneralTask: (id) => {
        set(s => ({ generalTasks: s.generalTasks.filter(t => t.id !== id) }));
        supabase.from('general_tasks').delete().eq('id', id);
      },

      updateGeneralTask: (id, updates) => {
        set(s => ({ generalTasks: s.generalTasks.map(t => t.id === id ? { ...t, ...updates } : t) }));
        const task = get().generalTasks.find(t => t.id === id);
        if (task) supabase.from('general_tasks').upsert(generalTaskToDb(task));
      },

      // ── Notes ────────────────────────────────────────────────────────────────
      addNote: (leadId, content) => {
        const now = new Date().toISOString().split('T')[0];
        const currentUser = get().users.find(u => u.id === get().currentUserId);
        const author = currentUser?.name ?? 'Unknown';
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId
              ? { ...l, notes: [{ id: generateId(), content, date: now, author }, ...l.notes] }
              : l
          ),
        }));
        syncLead(leadId);
      },

      deleteNote: (leadId, noteId) => {
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, notes: l.notes.filter(n => n.id !== noteId) } : l
          ),
        }));
        syncLead(leadId);
      },

      // ── Materials ────────────────────────────────────────────────────────────
      addMaterial: (leadId, mat) => {
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, materials: [...l.materials, { ...mat, id: generateId() }] } : l
          ),
        }));
        syncLead(leadId);
      },

      updateMaterial: (leadId, matId, updates) => {
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId
              ? { ...l, materials: l.materials.map(m => m.id === matId ? { ...m, ...updates } : m) }
              : l
          ),
        }));
        syncLead(leadId);
      },

      deleteMaterial: (leadId, matId) => {
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, materials: l.materials.filter(m => m.id !== matId) } : l
          ),
        }));
        syncLead(leadId);
      },

      // ── Files ────────────────────────────────────────────────────────────────
      addFile: (leadId, file) => {
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, files: [...l.files, { ...file, id: generateId() }] } : l
          ),
        }));
        syncLead(leadId);
      },

      deleteFile: (leadId, fileId) => {
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, files: l.files.filter(f => f.id !== fileId) } : l
          ),
        }));
        syncLead(leadId);
      },

      // ── Photos ───────────────────────────────────────────────────────────────
      addPhoto: (leadId, photo) => {
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, photos: [...l.photos, { ...photo, id: generateId() }] } : l
          ),
        }));
        syncLead(leadId);
      },

      deletePhoto: (leadId, photoId) => {
        set(s => ({
          leads: s.leads.map(l =>
            l.id === leadId ? { ...l, photos: l.photos.filter(p => p.id !== photoId) } : l
          ),
        }));
        syncLead(leadId);
      },
    };
    },
    {
      name: 'proline-crm-auth',
      // Only persist auth state locally — everything else comes from Supabase
      partialize: (state) => ({
        currentUserId: state.currentUserId,
        apiKey: state.apiKey,
        currentPage: state.currentPage,
        pushEnabled: state.pushEnabled,
      }),
    }
  )
);

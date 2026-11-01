import { mergeLead, LeadConflict } from '../lib/leadMerge';
import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import type { Lead, Stage, Material, FileItem, Photo, Contact, AppUser, GeneralTask, TimesheetEntry, PaymentRun, WorkerPayment } from '../types';
import { generateId } from '../utils/helpers';
import { enableDeviceNotifications, getDeviceNotificationPermission, isMacApp, sendDeviceNotification } from '../utils/push';
import {
  supabase,
  leadToDb, dbToLead,
  contactToDb, dbToContact,
  generalTaskToDb, dbToGeneralTask,
  timesheetEntryToDb, dbToTimesheetEntry,
  paymentRunToDb, dbToPaymentRun,
  workerPaymentToDb, dbToWorkerPayment,
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
  ],
  'Paid': [
    'File all job paperwork',
    'Request customer review / referral',
    'Update job records',
  ],
};

function profileToUser(row: Record<string, unknown>): AppUser {
  return {
    id: row.id as string,
    name: row.name as string,
    username: (row.email ?? row.username ?? '') as string,
    passwordHash: '',
    role: row.role as AppUser['role'],
    createdAt: (row.created_at ?? '') as string,
    dayRate: row.day_rate as number | undefined,
    cisRate: row.cis_rate as 20 | 30 | undefined,
    utrNumber: row.utr_number as string | undefined,
    bankName: row.bank_name as string | undefined,
    bankAccountNumber: row.bank_account_number as string | undefined,
    bankSortCode: row.bank_sort_code as string | undefined,
    organisationId: row.organisation_id as string | undefined,
  };
}

// Re-export for components that imported GeneralTask from here
export type { GeneralTask };

interface Store {
  unsavedLeadIds: string[];
  retryLeadSaves: () => void;
  discardLeadDrafts: () => Promise<void>;
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
  simpleMode: boolean;
  setSimpleMode: (enabled: boolean) => void;
  searchQuery: string;
  toast: { message: string; type: 'success' | 'info' | 'error' } | null;

  login: (username: string, password: string) => Promise<boolean>;
  logout: () => void;
  addUser: (name: string, username: string, password: string, role: 'admin' | 'user') => Promise<{ ok: boolean; error?: string }>;
  deleteUser: (id: string) => void;
  addCasualWorker: (name: string, dayRate: number, cisRate: 20 | 30) => void;
  removeCasualWorker: (id: string) => void;
  changePassword: (id: string, newPassword: string) => Promise<void>;
  updateUserName: (id: string, name: string) => void;
  updateUserProfile: (id: string, updates: Partial<Pick<AppUser, 'dayRate' | 'cisRate' | 'utrNumber' | 'bankName' | 'bankAccountNumber' | 'bankSortCode'>>) => Promise<boolean>;

  pushEnabled: boolean;
  pushPreferences: {
    newLead: boolean;
    surveyBooked: boolean;
    jobWon: boolean;
    jobStarted: boolean;
    jobCompleted: boolean;
    paymentReceived: boolean;
  };
  enablePushNotifications: () => Promise<void>;
  disablePushNotifications: () => void;
  setPushPreference: (key: keyof Store['pushPreferences'], value: boolean) => void;

  addTimesheetEntry: (data: Omit<TimesheetEntry, 'id' | 'createdAt'>) => void;
  upsertTimesheetEntry: (data: Omit<TimesheetEntry, 'id' | 'createdAt'>) => void;
  deleteTimesheetEntry: (id: string) => void;

  paymentRuns: PaymentRun[];
  updatePaymentStatus: (userId: string, weekStart: string, status: PaymentRun['status']) => void;

  workerPayments: WorkerPayment[];
  addWorkerPayment: (userId: string, amount: number, date: string, notes?: string) => void;
  deleteWorkerPayment: (id: string) => void;
  linkMonzoTransaction: (paymentId: string, monzoTransactionId: string | null) => void;

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
  syncGeneralTask: (id: string) => void;

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
      const snapshots = new Map<string, Record<string, unknown>>();
      const newLeadIds = new Set<string>();
      const failedBases = new Map<string, Record<string, unknown>>();
      const writes = new Map<string, Promise<void>>();
      const syncLead = (leadId: string) => {
        const lead = get().leads.find(l => l.id === leadId);
        const base = snapshots.get(leadId);
        if (!lead || !base) { get().showToast('Refresh this job before editing.', 'error'); return; }
        const draft = leadToDb(lead);
        const owner = get().currentUserId;
        snapshots.set(leadId, draft);
        set(s => ({ unsavedLeadIds: [...new Set([...s.unsavedLeadIds, leadId])] }));
        const previous = writes.get(leadId) ?? Promise.resolve();
        const write = previous.then(async () => {
          try {
            if (!owner || owner !== get().currentUserId) return;
            if (failedBases.has(leadId)) throw new Error('Resolve the previous failed save first.');
            for (let attempt = 0; attempt < 3; attempt++) {
              let { data: latest, error: readError } = await supabase.from('leads').select('*').eq('id', leadId).maybeSingle();
              if (!readError && !latest && newLeadIds.has(leadId)) {
                const inserted = await supabase.from('leads').insert(draft).select('*').single();
                if (inserted.error?.code === '23505') continue;
                latest = inserted.data;
                readError = inserted.error;
              }
              if (readError || !latest) throw new Error('Job cannot be loaded. Check your connection and access.');
              if (owner !== get().currentUserId) return;
              const merged = mergeLead(base, draft, latest);
              merged.updated_at = new Date().toISOString();
              let request = supabase.from('leads').update(merged).eq('id', leadId);
              request = latest.updated_at == null ? request.is('updated_at', null) : request.eq('updated_at', latest.updated_at);
              const { data: saved, error } = await request.select('*');
              if (error) throw error;
              if (!saved?.length) continue;
              if (owner !== get().currentUserId) return;
              newLeadIds.delete(leadId);
              if (snapshots.get(leadId) === draft) {
                snapshots.set(leadId, saved[0]);
                set(s => ({ unsavedLeadIds: s.unsavedLeadIds.filter(id => id !== leadId) }));
                set(s => ({ leads: s.leads.map(l => l.id === leadId ? dbToLead(saved[0]) : l) }));
              }
              return;
            }
            throw new LeadConflict();
          } catch (error) {
            if (owner !== get().currentUserId) return;
            if (!failedBases.has(leadId)) failedBases.set(leadId, base);
            if (snapshots.get(leadId) === draft) snapshots.set(leadId, failedBases.get(leadId)!);
            get().showToast(error instanceof LeadConflict ? error.message : 'Save failed. Your draft is still on screen; check your connection before refreshing.', 'error');
          }
        });
        writes.set(leadId, write);
        void write.finally(() => { if (writes.get(leadId) === write) writes.delete(leadId); });
      };

      return {
      unsavedLeadIds: [],
      retryLeadSaves: () => { for (const id of get().unsavedLeadIds) if (!writes.has(id)) { failedBases.delete(id); syncLead(id); } },
      discardLeadDrafts: async () => {
        if (writes.size) { get().showToast('Wait for current saves to finish.', 'info'); return; }
        for (const id of get().unsavedLeadIds) {
          const { data, error } = await supabase.from('leads').select('*').eq('id', id).maybeSingle();
          if (!error && !data && newLeadIds.has(id)) {
            newLeadIds.delete(id); failedBases.delete(id); snapshots.delete(id);
            set(s => ({ leads: s.leads.filter(l => l.id !== id), unsavedLeadIds: s.unsavedLeadIds.filter(key => key !== id) }));
            continue;
          }
          if (error || !data) { get().showToast('Latest job could not be loaded.', 'error'); continue; }
          failedBases.delete(id);
          snapshots.set(id, data);
          set(s => ({ leads: s.leads.map(l => l.id === id ? dbToLead(data) : l), unsavedLeadIds: s.unsavedLeadIds.filter(key => key !== id) }));
        }
      },
      isLoaded: false,
      users: [],
      currentUserId: null,
      leads: [],
      contacts: [],
      generalTasks: [],
      timesheetEntries: [],
      paymentRuns: [],
      workerPayments: [],
      apiKey: '',
      pushEnabled: false,
      pushPreferences: {
        newLead: true,
        surveyBooked: true,
        jobWon: true,
        jobStarted: false,
        jobCompleted: true,
        paymentReceived: true,
      },
      selectedId: null,
      currentPage: 'pipeline',
      simpleMode: false,
      setSimpleMode: (enabled) => set({ simpleMode: enabled, currentPage: 'pipeline', selectedId: null }),
      searchQuery: '',
      toast: null,

      // ── Load all data from Supabase ─────────────────────────────────────────
      loadData: async () => {
        if (get().unsavedLeadIds.length) { get().showToast('Resolve unsaved job changes before refreshing.', 'error'); return; }
        const { data: sessionData } = await supabase.auth.getSession();
        const authUserId = sessionData.session?.user.id ?? null;
        if (!authUserId) {
          set({ unsavedLeadIds: [], currentUserId: null, users: [], leads: [], contacts: [], generalTasks: [], timesheetEntries: [], paymentRuns: [], workerPayments: [], isLoaded: true });
          return;
        }
        const usersRequest = supabase.from('profiles').select('*').eq('active', true);
        const [leadsRes, usersRes, contactsRes, tasksRes, timesheetRes, paymentRunsRes, workerPaymentsRes] = await Promise.all([
          supabase.from('leads').select('*').order('updated_at', { ascending: false }),
          usersRequest,
          supabase.from('contacts').select('*').order('created_at', { ascending: false }),
          supabase.from('general_tasks').select('*').order('created_at', { ascending: false }),
          supabase.from('timesheet_entries').select('*').order('date', { ascending: false }),
          supabase.from('payment_runs').select('*'),
          supabase.from('worker_payments').select('*').order('date', { ascending: false }),
        ]);

        if (leadsRes.error || usersRes.error) {
          console.error('loadData error:', leadsRes.error ?? usersRes.error);
          get().showToast('Failed to load data — check your connection', 'error');
          set({ isLoaded: true });
          return;
        }

        snapshots.clear();
        failedBases.clear();
        for (const row of leadsRes.data ?? []) snapshots.set(row.id, row);
        const leads = (leadsRes.data ?? []).map(r => dbToLead(r as Record<string, unknown>));
        const users = (usersRes.data ?? []).map(r => profileToUser(r as Record<string, unknown>));
        if (!users.some(u => u.id === authUserId)) { get().logout(); set({ isLoaded: true }); return; }
        const contacts = (contactsRes.data ?? []).map(r => dbToContact(r as Record<string, unknown>));
        if (tasksRes.error) {
          console.error('loadData tasks error:', tasksRes.error);
          get().showToast('Tasks failed to load — check your connection', 'error');
        }
        const generalTasks = (tasksRes.data ?? []).map(r => dbToGeneralTask(r as Record<string, unknown>));
        const timesheetEntries = (timesheetRes.data ?? []).map(r => dbToTimesheetEntry(r as Record<string, unknown>));
        const paymentRuns = (paymentRunsRes.data ?? []).map(r => dbToPaymentRun(r as Record<string, unknown>));
        const workerPayments = (workerPaymentsRes.data ?? []).map(r => dbToWorkerPayment(r as Record<string, unknown>));

        // Set job counter to 1 above the highest existing job number
        const maxNum = leads.reduce((max, l) => {
          const m = l.jobRef.match(/JOB-(\d+)/);
          return m ? Math.max(max, parseInt(m[1])) : max;
        }, 0);
        jobCounterN = maxNum + 1;

        const allContacts = contacts;

        set({ leads, users, contacts: allContacts, generalTasks, timesheetEntries, paymentRuns, workerPayments, currentUserId: authUserId ?? get().currentUserId, isLoaded: true });

        await supabase.removeAllChannels();
        // Real-time: keep leads in sync across devices/tabs without refresh
        supabase
          .channel('leads-realtime')
          .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'leads' }, ({ new: row }) => {
            if (writes.has(String(row.id)) || get().unsavedLeadIds.includes(String(row.id))) return;
            snapshots.set(String(row.id), row as Record<string, unknown>);
            const lead = dbToLead(row as Record<string, unknown>);
            const isNew = !get().leads.some(l => l.id === lead.id);
            set(s => {
              if (s.leads.find(l => l.id === lead.id)) return s;
              return { leads: [lead, ...s.leads] };
            });
            if (isNew && get().pushEnabled && get().pushPreferences.newLead) {
              void sendDeviceNotification('New Lead', `${lead.name} — ${lead.jobRef}`);
            }
          })
          .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'leads' }, ({ new: row }) => {
            if (writes.has(String(row.id)) || get().unsavedLeadIds.includes(String(row.id))) return;
            snapshots.set(String(row.id), row as Record<string, unknown>);
            const lead = dbToLead(row as Record<string, unknown>);
            const previous = get().leads.find(l => l.id === lead.id);
            set(s => ({ leads: s.leads.map(l => l.id === lead.id ? lead : l) }));
            if (previous && previous.stage !== lead.stage && get().pushEnabled) {
              const stageNotification: Partial<Record<Stage, { title: string; pref: keyof Store['pushPreferences'] }>> = {
                'Survey Booked': { title: 'Survey Booked', pref: 'surveyBooked' },
                Won: { title: 'Job Won', pref: 'jobWon' },
                'In Progress': { title: 'Job Started', pref: 'jobStarted' },
                Completed: { title: 'Job Completed', pref: 'jobCompleted' },
                'Waiting for Payment': { title: 'Job Completed', pref: 'jobCompleted' },
                Paid: { title: 'Payment Received', pref: 'paymentReceived' },
              };
              const notification = stageNotification[lead.stage];
              if (notification && get().pushPreferences[notification.pref]) {
                void sendDeviceNotification(notification.title, `${lead.name} — ${lead.jobRef}`);
              }
            }
          })
          .on('postgres_changes', { event: 'DELETE', schema: 'public', table: 'leads' }, ({ old: row }) => {
            set(s => ({ leads: s.leads.filter(l => l.id !== (row as Record<string, unknown>).id) }));
          })
          .subscribe();
      },

      // ── Auth ────────────────────────────────────────────────────────────────
      login: async (email, password) => {
        const { data, error } = await supabase.auth.signInWithPassword({ email, password });
        if (error || !data.user) return false;
        const { data: profile } = await supabase.from('profiles').select('*').eq('id', data.user.id).eq('active', true).single();
        if (!profile) { await supabase.auth.signOut({ scope: 'local' }); return false; }
        await get().loadData();
        return get().currentUserId === data.user.id;
      },

      logout: () => {
        void supabase.auth.signOut({ scope: 'local' });
        void supabase.removeAllChannels();
        set({ unsavedLeadIds: [], currentUserId: null, users: [], leads: [], contacts: [], generalTasks: [], timesheetEntries: [], paymentRuns: [], workerPayments: [] });
      },

      addUser: async (name, email, password, role) => {
        const { data, error } = await supabase.functions.invoke('worker-invite', {
          body: { action: 'create_user', name, email, password, role: role === 'user' ? 'worker' : role },
        });
        if (error || data?.error) return { ok: false, error: data?.error ?? error?.message ?? 'User creation failed' };
        await get().loadData();
        return { ok: true };
      },

      deleteUser: (id) => {
        void supabase.functions.invoke('worker-invite', { body: { action: 'deactivate', user_id: id } }).then(({ data, error }) => {
          if (error || data?.error) get().showToast(data?.error ?? 'Access removal failed', 'error');
          else set(s => ({ users: s.users.filter(u => u.id !== id) }));
        });
      },

      addCasualWorker: (name, dayRate, cisRate) => {
        void supabase.functions.invoke('worker-invite', { body: { action: 'create_user', name, email: '', password: '', role: 'labourer', day_rate: dayRate, cis_rate: cisRate } }).then(async ({ data, error }) => {
          if (error || data?.error) get().showToast(data?.error ?? 'Worker could not be added', 'error');
          else await get().loadData();
        });
      },

      // Deactivate access; preserve historical work and payment records.
      removeCasualWorker: (id) => { get().deleteUser(id); },

      changePassword: async (id, newPassword) => {
        if (id !== get().currentUserId) {
          throw new Error('Employees must reset their own password from the sign-in screen.');
        }
        const { error } = await supabase.auth.updateUser({ password: newPassword });
        if (error) throw error;
      },

      updateUserName: (id, name) => {
        void supabase.from('profiles').update({ name }).eq('id', id).select('id').single().then(({ error }) => {
          if (error) get().showToast('Name could not be saved', 'error');
          else set(s => ({ users: s.users.map(u => u.id === id ? { ...u, name } : u) }));
        });
      },

      updateUserProfile: async (id, updates) => {
        const dbUpdates: Record<string, unknown> = {};
        if (updates.dayRate !== undefined) dbUpdates.day_rate = updates.dayRate;
        if (updates.cisRate !== undefined) dbUpdates.cis_rate = updates.cisRate;
        if (updates.utrNumber !== undefined) dbUpdates.utr_number = updates.utrNumber;
        if (updates.bankName !== undefined) dbUpdates.bank_name = updates.bankName;
        if (updates.bankAccountNumber !== undefined) dbUpdates.bank_account_number = updates.bankAccountNumber;
        if (updates.bankSortCode !== undefined) dbUpdates.bank_sort_code = updates.bankSortCode;
        const { error } = await supabase.from('profiles').update(dbUpdates).eq('id', id).select('id').single();
        if (error) {
          console.error('updateUserProfile error:', error);
          get().showToast('Profile save failed — check your connection', 'error');
          return false;
        }
        set(s => ({ users: s.users.map(u => u.id === id ? { ...u, ...updates } : u) }));
        return true;
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

      updatePaymentStatus: (userId, weekStart, status) => {
        const now = new Date().toISOString().split('T')[0];
        const existing = get().paymentRuns.find(r => r.userId === userId && r.weekStart === weekStart);
        const run: PaymentRun = existing
          ? { ...existing, status, paidDate: status === 'paid' ? now : existing.paidDate }
          : { id: generateId(), userId, weekStart, status, paidDate: status === 'paid' ? now : undefined, createdAt: now };
        set(s => ({
          paymentRuns: existing
            ? s.paymentRuns.map(r => r.userId === userId && r.weekStart === weekStart ? run : r)
            : [...s.paymentRuns, run],
        }));
        supabase.from('payment_runs').upsert(paymentRunToDb(run), { onConflict: 'user_id,week_start' });
      },

      addWorkerPayment: (userId, amount, date, notes) => {
        const now = new Date().toISOString().split('T')[0];
        const payment: WorkerPayment = { id: generateId(), userId, amount, date, notes, createdAt: now };
        set(s => ({ workerPayments: [payment, ...s.workerPayments] }));
        supabase.from('worker_payments').insert(workerPaymentToDb(payment)).then(({ error }) => {
          if (error) {
            console.error('addWorkerPayment error:', error);
            get().showToast('Payment save failed — check your connection', 'error');
          }
        });
      },

      deleteWorkerPayment: (id) => {
        set(s => ({ workerPayments: s.workerPayments.filter(p => p.id !== id) }));
        supabase.from('worker_payments').delete().eq('id', id).then(({ error }) => {
          if (error) console.error('deleteWorkerPayment error:', error);
        });
      },

      linkMonzoTransaction: (paymentId, monzoTransactionId) => {
        set(s => ({
          workerPayments: s.workerPayments.map(p =>
            p.id === paymentId ? { ...p, monzoTransactionId: monzoTransactionId ?? undefined } : p
          ),
        }));
        supabase.from('worker_payments')
          .update({ monzo_transaction_id: monzoTransactionId })
          .eq('id', paymentId)
          .then(({ error }) => { if (error) console.error('linkMonzoTransaction error:', error); });
      },

      enablePushNotifications: async () => {
        const result = await enableDeviceNotifications();
        if (!result.enabled) {
          if (result.denied || await getDeviceNotificationPermission() === 'denied') {
            get().showToast('Notifications blocked — allow in device Settings', 'error');
          }
          return;
        }
        if (result.native) {
          set({ pushEnabled: true });
          get().showToast('Mac notifications enabled');
          void sendDeviceNotification('ProLine CRM', 'Native Mac notifications are now enabled.');
          return;
        }
        const subscription = result.subscription;
        if (!subscription) return;
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

      disablePushNotifications: () => {
        if (!isMacApp() && 'serviceWorker' in navigator) {
          navigator.serviceWorker.ready.then(reg =>
            reg.pushManager.getSubscription().then(sub => {
              if (sub) {
                supabase.from('push_subscriptions').delete().eq('endpoint', sub.endpoint);
                sub.unsubscribe();
              }
            })
          );
        }
        set({ pushEnabled: false });
        get().showToast('Push notifications disabled', 'info');
      },

      setPushPreference: (key, value) =>
        set(s => ({ pushPreferences: { ...s.pushPreferences, [key]: value } })),

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
        const now = new Date().toISOString();
        const lead: Lead = {
          ...data, id: generateId(), jobRef: ref, createdAt: now, updatedAt: now,
          tasks: [], photos: [], notes: [], files: [], materials: [],
        };
        set(s => ({ leads: [lead, ...s.leads] }));
        snapshots.set(lead.id, leadToDb(lead));
        newLeadIds.add(lead.id);
        syncLead(lead.id);
        get().upsertContact({ name: data.name, phone: data.phone, email: data.email, address: data.address });
        get().showToast(`Saving new lead: ${data.name}`, 'info');
        // Push notification for new leads is handled by the Supabase DB trigger
        // so it fires regardless of whether the lead came from the CRM or another source.
      },

      updateLead: (id, updates) => {
        const updatedAt = new Date().toISOString().split('T')[0];
        set(s => ({
          leads: s.leads.map(l => l.id === id ? { ...l, ...updates, updatedAt } : l),
        }));
        syncLead(id);
      },

      deleteLead: (id) => {
        const snapshot = get().leads.find(l => l.id === id);
        set(s => ({ leads: s.leads.filter(l => l.id !== id), selectedId: s.selectedId === id ? null : s.selectedId }));
        supabase.from('leads').delete().eq('id', id).then(({ error }) => {
          if (error) {
            console.error('deleteLead sync error:', error);
            if (snapshot) set(s => ({ leads: [snapshot, ...s.leads] }));
            get().showToast('Delete failed — check your connection', 'error');
          }
        });
        get().showToast('Lead deleted', 'info');
      },

      moveToStage: (id, stage) => {
        const lead = get().leads.find(l => l.id === id);
        if (!lead) return;
        const now = new Date().toISOString().split('T')[0];
        const updates: Partial<Lead> = { stage, updatedAt: now };
        if (stage === 'Won') updates.wonDate = now;
        if (stage === 'In Progress' && !lead.startDate) updates.startDate = now;
        if ((stage === 'Completed' || stage === 'Waiting for Payment') && !lead.completedDate) updates.completedDate = now;
        if (stage === 'Paid') { updates.paidDate = now; updates.balance = 0; }
        const customTasks = lead.tasks.filter(t => !t.isTemplate);
        const newTemplateTasks = (STAGE_TASKS[stage] ?? []).map(title => ({
          id: generateId(), title, completed: false, isTemplate: true as const,
        }));
        updates.tasks = [...newTemplateTasks, ...customTasks];
        set(s => ({ leads: s.leads.map(l => l.id === id ? { ...l, ...updates } : l) }));
        syncLead(id);
        get().showToast(`Moved to ${stage}`);
        const pushTitles: Partial<Record<Stage, { title: string; pref: keyof Store['pushPreferences'] }>> = {
          'Survey Booked': { title: 'Survey Booked',   pref: 'surveyBooked' },
          Won:             { title: 'Job Won',          pref: 'jobWon' },
          'In Progress':   { title: 'Job Started',      pref: 'jobStarted' },
          Completed:       { title: 'Job Completed',    pref: 'jobCompleted' },
          'Waiting for Payment': { title: 'Job Completed', pref: 'jobCompleted' },
          Paid:            { title: 'Payment Received', pref: 'paymentReceived' },
        };
        const pushEntry = pushTitles[stage];
        if (pushEntry && get().pushEnabled && get().pushPreferences[pushEntry.pref]) {
          void sendDeviceNotification(pushEntry.title, `${lead.name} — ${lead.jobRef}`);
          supabase.functions.invoke('send-push', {
            body: { title: pushEntry.title, body: `${lead.name} — ${lead.jobRef}` },
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
      syncGeneralTask: (id) => {
        const task = get().generalTasks.find(t => t.id === id);
        if (!task) return;
        supabase.from('general_tasks').upsert(generalTaskToDb(task))
          .then(({ error }) => {
            if (error) {
              console.error('General task sync error:', error);
              get().showToast('Task not saved — check your connection', 'error');
            }
          });
      },

      addGeneralTask: (data) => {
        const now = new Date().toISOString().split('T')[0];
        const task: GeneralTask = { ...data, id: generateId(), completed: false, createdAt: now };
        set(s => ({ generalTasks: [task, ...s.generalTasks] }));
        get().syncGeneralTask(task.id);
      },

      toggleGeneralTask: (id) => {
        set(s => ({
          generalTasks: s.generalTasks.map(t => {
            if (t.id !== id) return t;
            const now = new Date().toISOString().split('T')[0];
            return { ...t, completed: !t.completed, completedDate: !t.completed ? now : undefined };
          }),
        }));
        get().syncGeneralTask(id);
      },

      deleteGeneralTask: (id) => {
        set(s => ({ generalTasks: s.generalTasks.filter(t => t.id !== id) }));
        supabase.from('general_tasks').delete().eq('id', id)
          .then(({ error }) => {
            if (error) {
              console.error('General task delete error:', error);
              get().showToast('Delete failed — check your connection', 'error');
            }
          });
      },

      updateGeneralTask: (id, updates) => {
        set(s => ({ generalTasks: s.generalTasks.map(t => t.id === id ? { ...t, ...updates } : t) }));
        get().syncGeneralTask(id);
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
        apiKey: state.apiKey,
        currentPage: state.currentPage,
        simpleMode: state.simpleMode,
        pushEnabled: state.pushEnabled,
        pushPreferences: state.pushPreferences,
      }),
    }
  )
);

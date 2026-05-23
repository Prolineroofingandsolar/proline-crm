import { useState, useMemo } from 'react';
import { ChevronLeft, ChevronRight, Clock, Pencil, Check, X, Trash2, UserPlus, Banknote, CalendarCheck, CheckCircle2 } from 'lucide-react';
import { useStore } from '../store/useStore';
import type { AppUser } from '../types';

// ── Date helpers ────────────────────────────────────────────────────────────────

function getMonday(d: Date): Date {
  const day = d.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  const mon = new Date(d);
  mon.setDate(d.getDate() + diff);
  return mon;
}

function addDays(d: Date, n: number): Date {
  const r = new Date(d);
  r.setDate(r.getDate() + n);
  return r;
}

function toYMD(d: Date): string {
  return d.toISOString().split('T')[0];
}

function fmtDate(d: Date): string {
  return d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
}

function fmtRange(mon: Date): string {
  const sun = addDays(mon, 6);
  return `${mon.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })} – ${sun.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}`;
}

function calcNet(gross: number, cisRate: number) {
  const deduction = gross * (cisRate / 100);
  return { gross, deduction, net: gross - deduction };
}

// ── Profile edit modal ──────────────────────────────────────────────────────────

interface ProfileModalProps {
  user: AppUser;
  onClose: () => void;
}

function ProfileModal({ user, onClose }: ProfileModalProps) {
  const { updateUserProfile, showToast } = useStore();
  const [dayRate, setDayRate] = useState(String(user.dayRate ?? ''));
  const [cisRate, setCisRate] = useState<20 | 30>(user.cisRate ?? 20);
  const [utr, setUtr] = useState(user.utrNumber ?? '');
  const [bank, setBank] = useState(user.bankName ?? '');
  const [account, setAccount] = useState(user.bankAccountNumber ?? '');
  const [sortCode, setSortCode] = useState(user.bankSortCode ?? '');

  const save = () => {
    updateUserProfile(user.id, {
      dayRate: dayRate ? parseFloat(dayRate) : undefined,
      cisRate,
      utrNumber: utr || undefined,
      bankName: bank || undefined,
      bankAccountNumber: account || undefined,
      bankSortCode: sortCode || undefined,
    });
    showToast('Profile updated');
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4" style={{ background: 'rgba(0,0,0,0.5)' }}>
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h2 className="text-base font-semibold text-gray-900">Edit Payment Details</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600"><X size={18} /></button>
        </div>
        <div className="p-5 space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">Day Rate (£ gross)</label>
              <input
                type="number" min="0" step="0.01" value={dayRate}
                onChange={e => setDayRate(e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500"
                placeholder="e.g. 250"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">CIS Deduction Rate</label>
              <div className="flex rounded-lg overflow-hidden border border-gray-200 h-[38px]">
                <button
                  type="button"
                  onClick={() => setCisRate(20)}
                  className={`flex-1 text-sm font-medium transition-colors ${cisRate === 20 ? 'bg-orange-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}
                >
                  20%
                </button>
                <button
                  type="button"
                  onClick={() => setCisRate(30)}
                  className={`flex-1 text-sm font-medium transition-colors ${cisRate === 30 ? 'bg-orange-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}
                >
                  30%
                </button>
              </div>
            </div>
          </div>

          {dayRate && (
            <div className="bg-gray-50 rounded-xl px-4 py-3 flex justify-between text-sm">
              <div className="space-y-0.5">
                <div className="text-gray-500">Gross (full day)</div>
                <div className="text-gray-500">CIS ({cisRate}%)</div>
                <div className="font-semibold text-gray-800">Net take-home</div>
              </div>
              <div className="space-y-0.5 text-right">
                <div className="text-gray-700">£{parseFloat(dayRate).toFixed(0)}</div>
                <div className="text-red-500">−£{(parseFloat(dayRate) * cisRate / 100).toFixed(0)}</div>
                <div className="font-semibold text-green-700">£{(parseFloat(dayRate) * (1 - cisRate / 100)).toFixed(0)}</div>
              </div>
            </div>
          )}

          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">UTR Number</label>
            <input
              type="text" value={utr}
              onChange={e => setUtr(e.target.value)}
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500"
              placeholder="e.g. 1234567890"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">Bank Name</label>
            <input
              type="text" value={bank}
              onChange={e => setBank(e.target.value)}
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500"
              placeholder="e.g. Barclays"
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">Account Number</label>
              <input
                type="text" value={account}
                onChange={e => setAccount(e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500"
                placeholder="12345678"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">Sort Code</label>
              <input
                type="text" value={sortCode}
                onChange={e => setSortCode(e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500"
                placeholder="12-34-56"
              />
            </div>
          </div>
        </div>
        <div className="flex gap-3 px-5 py-4 border-t border-gray-100">
          <button onClick={onClose} className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2 rounded-xl hover:bg-gray-50 transition-colors">
            Cancel
          </button>
          <button onClick={save} className="flex-1 bg-orange-600 text-white text-sm font-medium py-2 rounded-xl hover:bg-orange-700 transition-colors">
            Save
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Day row ─────────────────────────────────────────────────────────────────────

interface DayRowProps {
  date: string;
  label: string;
  entry?: { id: string; leadId: string; type: 'full' | 'half'; amount: number };
  dayRate: number;
  cisRate: number;
  leads: { id: string; name: string; jobRef: string }[];
  onSave: (leadId: string, type: 'full' | 'half', amount: number) => void;
  onDelete: (id: string) => void;
  readOnly?: boolean;
}

function DayRow({ date, label, entry, dayRate, cisRate, leads, onSave, onDelete, readOnly }: DayRowProps) {
  const today = toYMD(new Date());
  const isPast = date <= today;
  const isWeekend = (() => { const d = new Date(date + 'T00:00:00'); return d.getDay() === 0 || d.getDay() === 6; })();
  const [editing, setEditing] = useState(false);
  const [selectedLead, setSelectedLead] = useState(entry?.leadId ?? '');
  const [type, setType] = useState<'full' | 'half'>(entry?.type ?? 'full');

  const previewGross = dayRate * (type === 'full' ? 1 : 0.5);
  const previewNet = previewGross * (1 - cisRate / 100);

  const startEdit = () => {
    setSelectedLead(entry?.leadId ?? '');
    setType(entry?.type ?? 'full');
    setEditing(true);
  };

  const save = () => {
    if (!selectedLead) return;
    const gross = dayRate * (type === 'full' ? 1 : 0.5);
    onSave(selectedLead, type, gross);
    setEditing(false);
  };

  if (editing && !readOnly) {
    return (
      <div className={`px-4 py-3 border-b border-gray-50 last:border-0 space-y-2 ${isWeekend ? 'bg-gray-50/60' : ''}`}>
        <div className="flex items-center gap-2">
          <div className="w-20 shrink-0">
            <div className={`text-xs font-semibold ${date === today ? 'text-orange-600' : isWeekend ? 'text-gray-400' : 'text-gray-700'}`}>{label.split(' ')[0]}</div>
            <div className="text-[11px] text-gray-400">{label.split(' ').slice(1).join(' ')}</div>
          </div>
          <select
            value={selectedLead}
            onChange={e => setSelectedLead(e.target.value)}
            className="flex-1 min-w-0 border border-gray-200 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500 bg-white"
          >
            <option value="">Select job…</option>
            {leads.map(l => (
              <option key={l.id} value={l.id}>{l.jobRef} – {l.name}</option>
            ))}
          </select>
          <div className="flex rounded-lg overflow-hidden border border-gray-200 shrink-0">
            <button onClick={() => setType('half')} className={`px-3 py-1.5 text-xs font-medium transition-colors ${type === 'half' ? 'bg-orange-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>Half</button>
            <button onClick={() => setType('full')} className={`px-3 py-1.5 text-xs font-medium transition-colors ${type === 'full' ? 'bg-orange-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>Full</button>
          </div>
          <button onClick={save} disabled={!selectedLead} className="text-green-600 hover:text-green-700 disabled:opacity-30 shrink-0"><Check size={16} /></button>
          <button onClick={() => setEditing(false)} className="text-gray-400 hover:text-gray-600 shrink-0"><X size={16} /></button>
        </div>
        {selectedLead && (
          <div className="ml-20 flex items-center gap-4 text-xs">
            <span className="text-gray-500">Gross <span className="font-semibold text-gray-700">£{previewGross.toFixed(0)}</span></span>
            <span className="text-red-400">CIS {cisRate}% −£{(previewGross * cisRate / 100).toFixed(0)}</span>
            <span className="text-green-600 font-semibold">Net £{previewNet.toFixed(0)}</span>
          </div>
        )}
      </div>
    );
  }

  return (
    <div className={`flex items-center gap-3 px-4 py-3 border-b border-gray-50 last:border-0 ${isWeekend ? 'bg-gray-50/60' : ''}`}>
      <div className="w-20 shrink-0">
        <div className={`text-xs font-semibold ${date === today ? 'text-orange-600' : isWeekend ? 'text-gray-400' : 'text-gray-700'}`}>{label.split(' ')[0]}</div>
        <div className="text-[11px] text-gray-400">{label.split(' ').slice(1).join(' ')}</div>
      </div>

      {entry ? (
        <>
          <div className="flex-1 min-w-0">
            <div className="text-sm font-medium text-gray-800 truncate">
              {leads.find(l => l.id === entry.leadId)?.name ?? 'Unknown job'}
            </div>
            <div className="text-[11px] text-gray-400">
              {leads.find(l => l.id === entry.leadId)?.jobRef} · {entry.type === 'full' ? 'Full day' : 'Half day'}
            </div>
          </div>
          <div className="text-right shrink-0">
            <div className="text-sm font-bold text-gray-900">£{entry.amount.toFixed(0)}</div>
            <div className="text-[11px] text-green-600 font-medium">£{calcNet(entry.amount, cisRate).net.toFixed(0)} net</div>
          </div>
          {!readOnly && (
            <>
              <button onClick={startEdit} className="text-gray-300 hover:text-gray-500 shrink-0"><Pencil size={14} /></button>
              <button onClick={() => onDelete(entry.id)} className="text-gray-300 hover:text-red-500 shrink-0"><Trash2 size={14} /></button>
            </>
          )}
        </>
      ) : (
        <>
          <div className="flex-1 text-sm text-gray-300 italic">No entry</div>
          {!readOnly && isPast && (
            <button onClick={startEdit} className="text-xs text-orange-500 hover:text-orange-700 font-medium shrink-0">+ Add</button>
          )}
        </>
      )}
    </div>
  );
}

// ── Payments tab ─────────────────────────────────────────────────────────────

type PayFilter = 'all' | 'due' | 'scheduled' | 'paid';

const STATUS_META: Record<string, { label: string; pill: string; icon: React.ReactNode }> = {
  due:       { label: 'Due',       pill: 'bg-amber-100 text-amber-700 border-amber-200',   icon: <Clock size={11} /> },
  scheduled: { label: 'Scheduled', pill: 'bg-blue-100 text-blue-700 border-blue-200',      icon: <CalendarCheck size={11} /> },
  paid:      { label: 'Paid',      pill: 'bg-green-100 text-green-700 border-green-200',   icon: <CheckCircle2 size={11} /> },
};

function PaymentsTab({ users, timesheetEntries, paymentRuns, updatePaymentStatus }: {
  users: AppUser[];
  timesheetEntries: ReturnType<typeof useStore>['timesheetEntries'];
  paymentRuns: ReturnType<typeof useStore>['paymentRuns'];
  updatePaymentStatus: ReturnType<typeof useStore>['updatePaymentStatus'];
}) {
  const [filter, setFilter] = useState<PayFilter>('all');

  const summaries = useMemo(() => {
    const map = new Map<string, { userId: string; weekStart: string; entries: typeof timesheetEntries }>();
    for (const entry of timesheetEntries) {
      const d = new Date(entry.date + 'T00:00:00');
      const ws = toYMD(getMonday(d));
      const key = `${entry.userId}_${ws}`;
      if (!map.has(key)) map.set(key, { userId: entry.userId, weekStart: ws, entries: [] });
      map.get(key)!.entries.push(entry);
    }
    return Array.from(map.values()).map(({ userId, weekStart, entries }) => {
      const user = users.find(u => u.id === userId);
      const days = entries.reduce((s, e) => s + (e.type === 'full' ? 1 : 0.5), 0);
      const gross = entries.reduce((s, e) => s + e.amount, 0);
      const rate = user?.cisRate ?? 20;
      const net = gross * (1 - rate / 100);
      const run = paymentRuns.find(r => r.userId === userId && r.weekStart === weekStart);
      const status = (run?.status ?? 'due') as 'due' | 'scheduled' | 'paid';
      // week range label
      const mon = new Date(weekStart + 'T00:00:00');
      const sun = addDays(mon, 6);
      const weekLabel = fmtRange(mon);
      const weekEndLabel = sun.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
      return { userId, weekStart, user, days, gross, net, rate, status, paidDate: run?.paidDate, weekLabel, weekEndLabel };
    }).sort((a, b) => b.weekStart.localeCompare(a.weekStart) || (a.user?.name ?? '').localeCompare(b.user?.name ?? ''));
  }, [users, timesheetEntries, paymentRuns]);

  const filtered = filter === 'all' ? summaries : summaries.filter(s => s.status === filter);

  const totals = useMemo(() => ({
    due:       summaries.filter(s => s.status === 'due').reduce((t, s) => t + s.net, 0),
    scheduled: summaries.filter(s => s.status === 'scheduled').reduce((t, s) => t + s.net, 0),
    paid:      summaries.filter(s => s.status === 'paid').reduce((t, s) => t + s.net, 0),
  }), [summaries]);

  return (
    <div className="space-y-4">
      {/* Summary cards */}
      <div className="grid grid-cols-3 gap-3">
        {(['due', 'scheduled', 'paid'] as const).map(s => {
          const m = STATUS_META[s];
          const amt = totals[s];
          return (
            <button key={s} onClick={() => setFilter(f => f === s ? 'all' : s)}
              className={`rounded-2xl p-3 text-center border transition-all ${
                filter === s ? 'ring-2 ring-orange-500' : ''
              } ${
                s === 'due' ? 'bg-amber-50 border-amber-100' :
                s === 'scheduled' ? 'bg-blue-50 border-blue-100' :
                'bg-green-50 border-green-100'
              }`}
            >
              <div className={`text-xs font-semibold uppercase tracking-wide mb-1 ${
                s === 'due' ? 'text-amber-600' : s === 'scheduled' ? 'text-blue-600' : 'text-green-700'
              }`}>{m.label}</div>
              <div className={`text-lg font-bold ${
                s === 'due' ? 'text-amber-700' : s === 'scheduled' ? 'text-blue-700' : 'text-green-700'
              }`}>£{amt.toFixed(0)}</div>
              <div className="text-[10px] text-gray-400 mt-0.5">
                {summaries.filter(x => x.status === s).length} payment{summaries.filter(x => x.status === s).length !== 1 ? 's' : ''}
              </div>
            </button>
          );
        })}
      </div>

      {/* Filter pills */}
      <div className="flex gap-1.5">
        {(['all', 'due', 'scheduled', 'paid'] as PayFilter[]).map(f => (
          <button key={f} onClick={() => setFilter(f)}
            className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors capitalize ${
              filter === f ? 'bg-orange-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
            }`}>
            {f === 'all' ? 'All' : STATUS_META[f].label}
            {f !== 'all' && <span className="ml-1 opacity-70">({summaries.filter(s => s.status === f).length})</span>}
          </button>
        ))}
      </div>

      {/* Payment rows */}
      {filtered.length === 0 ? (
        <div className="bg-white rounded-2xl border border-gray-100 p-8 text-center">
          <Banknote size={32} className="mx-auto text-gray-200 mb-2" />
          <p className="text-sm text-gray-400">No payments here yet</p>
          <p className="text-xs text-gray-300 mt-1">Payments appear once timesheet entries are logged</p>
        </div>
      ) : (
        <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
          {filtered.map((s, i) => {
            const meta = STATUS_META[s.status];
            const initials = (s.user?.name ?? '?').split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase();
            return (
              <div key={`${s.userId}_${s.weekStart}`}
                className={`flex items-center gap-3 px-4 py-3.5 ${i < filtered.length - 1 ? 'border-b border-gray-50' : ''}`}>
                {/* Avatar */}
                <div className="w-9 h-9 rounded-xl bg-orange-100 flex items-center justify-center text-orange-700 font-bold text-sm shrink-0">
                  {initials}
                </div>
                {/* Name + week */}
                <div className="flex-1 min-w-0">
                  <div className="text-sm font-semibold text-gray-800 truncate">{s.user?.name ?? 'Unknown'}</div>
                  <div className="text-[11px] text-gray-400">{s.weekLabel}</div>
                  <div className="text-[11px] text-gray-400">{s.days} {s.days === 1 ? 'day' : 'days'}</div>
                </div>
                {/* Amounts */}
                <div className="text-right shrink-0 mr-1 hidden sm:block">
                  <div className="text-xs text-gray-400">£{s.gross.toFixed(0)} gross</div>
                  <div className="text-xs text-red-400">−£{(s.gross - s.net).toFixed(0)} CIS {s.rate}%</div>
                  <div className="text-sm font-bold text-gray-800">£{s.net.toFixed(0)} net</div>
                </div>
                {/* Status + action */}
                <div className="shrink-0 flex flex-col items-end gap-1.5 min-w-[90px]">
                  <span className={`inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full border ${meta.pill}`}>
                    {meta.icon} {meta.label}
                  </span>
                  {s.status === 'due' && (
                    <button
                      onClick={() => updatePaymentStatus(s.userId, s.weekStart, 'scheduled')}
                      className="text-[11px] font-semibold text-blue-600 hover:text-blue-800 bg-blue-50 hover:bg-blue-100 px-2 py-0.5 rounded-md transition-colors"
                    >
                      Schedule
                    </button>
                  )}
                  {s.status === 'scheduled' && (
                    <button
                      onClick={() => updatePaymentStatus(s.userId, s.weekStart, 'paid')}
                      className="text-[11px] font-semibold text-green-600 hover:text-green-800 bg-green-50 hover:bg-green-100 px-2 py-0.5 rounded-md transition-colors"
                    >
                      Mark Paid
                    </button>
                  )}
                  {s.status === 'paid' && s.paidDate && (
                    <span className="text-[10px] text-gray-400">
                      {new Date(s.paidDate + 'T00:00:00').toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}
                    </span>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ── Main page ───────────────────────────────────────────────────────────────────

export default function TimesheetPage() {
  const { users, currentUserId, leads, timesheetEntries, paymentRuns, upsertTimesheetEntry, deleteTimesheetEntry, updatePaymentStatus, addCasualWorker, removeCasualWorker } = useStore();
  const currentUser = users.find(u => u.id === currentUserId)!;
  const isAdmin = currentUser?.role === 'admin';

  const [tab, setTab] = useState<'timesheet' | 'payments'>('timesheet');

  const [weekStart, setWeekStart] = useState<Date>(() => getMonday(new Date()));
  const [viewUserId, setViewUserId] = useState(currentUserId ?? '');
  const [showProfile, setShowProfile] = useState(false);
  const [showAddCasual, setShowAddCasual] = useState(false);
  const [casualName, setCasualName] = useState('');
  const [casualDayRate, setCasualDayRate] = useState('');
  const [casualCisRate, setCasualCisRate] = useState<20 | 30>(20);

  const casualWorkers = useMemo(() => users.filter(u => u.role === 'casual'), [users]);

  const saveCasualWorker = () => {
    if (!casualName.trim() || !casualDayRate) return;
    addCasualWorker(casualName.trim(), parseFloat(casualDayRate), casualCisRate);
    setCasualName('');
    setCasualDayRate('');
    setCasualCisRate(20);
    setShowAddCasual(false);
  };

  const viewUser = users.find(u => u.id === viewUserId) ?? currentUser;
  const dayRate = viewUser?.dayRate ?? 0;
  const cisRate = viewUser?.cisRate ?? 20;

  const weekDays = useMemo(() => Array.from({ length: 7 }, (_, i) => {
    const d = addDays(weekStart, i);
    return { date: toYMD(d), label: fmtDate(d) };
  }), [weekStart]);

  const weekEntries = useMemo(() =>
    timesheetEntries.filter(e => e.userId === viewUserId && weekDays.some(d => d.date === e.date)),
    [timesheetEntries, viewUserId, weekDays]
  );

  const totalDays = weekEntries.reduce((sum, e) => sum + (e.type === 'full' ? 1 : 0.5), 0);
  const totalGross = weekEntries.reduce((sum, e) => sum + e.amount, 0);
  const totalDeduction = totalGross * (cisRate / 100);
  const totalNet = totalGross - totalDeduction;

  const leadOptions = leads.map(l => ({ id: l.id, name: l.name, jobRef: l.jobRef }));
  const canEdit = viewUserId === currentUserId || isAdmin;

  const adminSummary = useMemo(() => {
    if (!isAdmin) return [];
    return users.filter(u => u.role !== 'casual').map(u => {
      const entries = timesheetEntries.filter(e => e.userId === u.id && weekDays.some(d => d.date === e.date));
      const days = entries.reduce((s, e) => s + (e.type === 'full' ? 1 : 0.5), 0);
      const gross = entries.reduce((s, e) => s + e.amount, 0);
      const rate = u.cisRate ?? 20;
      const net = gross * (1 - rate / 100);
      return { user: u, days, gross, net, rate };
    }).filter(r => r.days > 0);
  }, [isAdmin, users, timesheetEntries, weekDays]);

  return (
    <div className="h-full overflow-y-auto bg-gray-50">
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">

        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl bg-orange-600 flex items-center justify-center">
              <Clock size={18} className="text-white" />
            </div>
            <div>
              <h1 className="text-lg font-bold text-gray-900">Timesheet</h1>
              <p className="text-xs text-gray-500">Track your daily hours</p>
            </div>
          </div>
          {isAdmin && tab === 'timesheet' && (
            <select
              value={viewUserId}
              onChange={e => setViewUserId(e.target.value)}
              className="border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-orange-500"
            >
              <optgroup label="Team">
                {users.filter(u => u.role !== 'casual').map(u => <option key={u.id} value={u.id}>{u.name}</option>)}
              </optgroup>
              {casualWorkers.length > 0 && (
                <optgroup label="Casual Workers">
                  {casualWorkers.map(u => <option key={u.id} value={u.id}>{u.name}</option>)}
                </optgroup>
              )}
            </select>
          )}
        </div>

        {/* Tab switcher — admin only */}
        {isAdmin && (
          <div className="flex gap-1 p-1 bg-gray-100 rounded-xl">
            <button
              onClick={() => setTab('timesheet')}
              className={`flex-1 flex items-center justify-center gap-1.5 py-2 text-sm font-semibold rounded-lg transition-colors ${
                tab === 'timesheet' ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              <Clock size={14} /> Timesheet
            </button>
            <button
              onClick={() => setTab('payments')}
              className={`flex-1 flex items-center justify-center gap-1.5 py-2 text-sm font-semibold rounded-lg transition-colors ${
                tab === 'payments' ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              <Banknote size={14} /> Payments
            </button>
          </div>
        )}

        {tab === 'payments' && isAdmin && (
          <PaymentsTab
            users={users}
            timesheetEntries={timesheetEntries}
            paymentRuns={paymentRuns}
            updatePaymentStatus={updatePaymentStatus}
          />
        )}

        {/* Timesheet content */}
        {tab === 'timesheet' && <>

        {/* Profile card */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
          <div className="flex items-center justify-between mb-3">
            <div className="text-sm font-semibold text-gray-700">{viewUser?.name}</div>
            {(viewUserId === currentUserId || isAdmin) && (
              <button onClick={() => setShowProfile(true)} className="flex items-center gap-1.5 text-xs text-orange-600 hover:text-orange-700 font-medium">
                <Pencil size={12} /> Edit details
              </button>
            )}
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-3">
            <div className="bg-gray-50 rounded-xl p-3">
              <div className="text-[10px] text-gray-500 font-medium uppercase tracking-wide">Gross day rate</div>
              <div className="text-base font-bold text-gray-800">{dayRate > 0 ? `£${dayRate.toFixed(0)}` : '–'}</div>
            </div>
            <div className="bg-red-50 rounded-xl p-3">
              <div className="text-[10px] text-red-500 font-medium uppercase tracking-wide">CIS deduction</div>
              <div className="text-base font-bold text-red-600">{cisRate}%</div>
            </div>
            <div className="bg-green-50 rounded-xl p-3">
              <div className="text-[10px] text-green-600 font-medium uppercase tracking-wide">Net day rate</div>
              <div className="text-base font-bold text-green-700">{dayRate > 0 ? `£${(dayRate * (1 - cisRate / 100)).toFixed(0)}` : '–'}</div>
            </div>
            <div className="bg-gray-50 rounded-xl p-3">
              <div className="text-[10px] text-gray-500 font-medium uppercase tracking-wide">UTR</div>
              <div className="text-sm font-semibold text-gray-700 truncate">{viewUser?.utrNumber || '–'}</div>
            </div>
          </div>
          {viewUser?.bankName && (
            <div className="text-xs text-gray-400 bg-gray-50 rounded-xl px-3 py-2">
              <span className="font-medium text-gray-600">{viewUser.bankName}</span>
              {viewUser.bankSortCode ? ` · ${viewUser.bankSortCode}` : ''}
              {viewUser.bankAccountNumber ? ` · ${viewUser.bankAccountNumber}` : ''}
            </div>
          )}
        </div>

        {/* Week navigation */}
        <div className="flex items-center justify-between bg-white rounded-2xl shadow-sm border border-gray-100 px-4 py-3">
          <button onClick={() => setWeekStart(d => addDays(d, -7))} className="w-8 h-8 flex items-center justify-center rounded-lg hover:bg-gray-100 transition-colors text-gray-500">
            <ChevronLeft size={18} />
          </button>
          <div className="text-sm font-semibold text-gray-700">{fmtRange(weekStart)}</div>
          <button onClick={() => setWeekStart(d => addDays(d, 7))} className="w-8 h-8 flex items-center justify-center rounded-lg hover:bg-gray-100 transition-colors text-gray-500">
            <ChevronRight size={18} />
          </button>
        </div>

        {/* Day rows */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          {dayRate === 0 && canEdit && (
            <div className="px-4 py-3 bg-amber-50 border-b border-amber-100 text-xs text-amber-700 font-medium">
              Set your day rate in Edit details above to log time.
            </div>
          )}
          {weekDays.map(({ date, label }) => {
            const entry = weekEntries.find(e => e.date === date);
            return (
              <DayRow
                key={date}
                date={date}
                label={label}
                entry={entry}
                dayRate={dayRate}
                cisRate={cisRate}
                leads={leadOptions}
                readOnly={!canEdit || dayRate === 0}
                onSave={(leadId, type, amount) => upsertTimesheetEntry({ userId: viewUserId, leadId, date, type, amount })}
                onDelete={deleteTimesheetEntry}
              />
            );
          })}
        </div>

        {/* Weekly totals */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-50 flex items-center justify-between">
            <div className="text-xs font-medium text-gray-500 uppercase tracking-wide">Week total</div>
            <div className="text-xs text-gray-400">{totalDays} {totalDays === 1 ? 'day' : 'days'}</div>
          </div>
          <div className="px-4 py-3 flex items-center justify-between border-b border-gray-50">
            <div className="text-sm text-gray-600">Gross pay</div>
            <div className="text-sm font-semibold text-gray-800">£{totalGross.toFixed(0)}</div>
          </div>
          <div className="px-4 py-3 flex items-center justify-between border-b border-gray-50">
            <div className="text-sm text-red-500">CIS deduction ({cisRate}%)</div>
            <div className="text-sm font-semibold text-red-500">−£{totalDeduction.toFixed(0)}</div>
          </div>
          <div className="px-4 py-3 flex items-center justify-between bg-green-50">
            <div className="text-sm font-bold text-green-800">Net pay (take home)</div>
            <div className="text-xl font-bold text-green-700">£{totalNet.toFixed(0)}</div>
          </div>
        </div>

        {/* Admin team summary */}
        {isAdmin && adminSummary.length > 0 && (
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-100">
              <div className="text-sm font-semibold text-gray-700">Team — This Week</div>
            </div>
            {adminSummary.map(({ user, days, gross, net, rate }) => (
              <div key={user.id} className="px-4 py-3 border-b border-gray-50 last:border-0">
                <div className="flex items-start justify-between mb-1">
                  <div>
                    <div className="text-sm font-medium text-gray-800">{user.name}</div>
                    <div className="text-[11px] text-gray-400">
                      {days} {days === 1 ? 'day' : 'days'}
                      {user.utrNumber ? ` · UTR: ${user.utrNumber}` : ''}
                    </div>
                    {user.bankName && (
                      <div className="text-[11px] text-gray-400">
                        {user.bankName}{user.bankSortCode ? ` · ${user.bankSortCode}` : ''}{user.bankAccountNumber ? ` · ${user.bankAccountNumber}` : ''}
                      </div>
                    )}
                  </div>
                  <div className="text-right">
                    <div className="text-xs text-gray-400">Gross £{gross.toFixed(0)}</div>
                    <div className="text-xs text-red-400">CIS {rate}% −£{(gross * rate / 100).toFixed(0)}</div>
                    <div className="text-sm font-bold text-green-700">£{net.toFixed(0)} net</div>
                  </div>
                </div>
              </div>
            ))}
            <div className="px-4 py-3 bg-green-50 flex items-center justify-between">
              <div>
                <div className="text-sm font-semibold text-green-800">Total payroll (net)</div>
                <div className="text-xs text-gray-500">Gross £{adminSummary.reduce((s, r) => s + r.gross, 0).toFixed(0)}</div>
              </div>
              <div className="text-xl font-bold text-green-700">
                £{adminSummary.reduce((s, r) => s + r.net, 0).toFixed(0)}
              </div>
            </div>
          </div>
        )}

        {/* Casual day workers — admin only */}
        {isAdmin && (
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
            <div className="flex items-center justify-between px-4 py-3 border-b border-gray-100">
              <div className="text-sm font-semibold text-gray-700">Casual Day Workers</div>
              <button
                onClick={() => setShowAddCasual(true)}
                className="flex items-center gap-1.5 text-xs font-semibold text-orange-600 hover:text-orange-700 transition-colors"
              >
                <UserPlus size={13} /> Add worker
              </button>
            </div>
            {casualWorkers.length === 0 ? (
              <div className="px-4 py-6 text-center text-sm text-gray-400 italic">
                No casual workers yet — add someone who does a day here and there
              </div>
            ) : (
              casualWorkers.map(worker => {
                const wEntries = timesheetEntries.filter(e => e.userId === worker.id && weekDays.some(d => d.date === e.date));
                const wDays = wEntries.reduce((s, e) => s + (e.type === 'full' ? 1 : 0.5), 0);
                const wGross = wEntries.reduce((s, e) => s + e.amount, 0);
                const wRate = worker.cisRate ?? 20;
                const wNet = wGross * (1 - wRate / 100);
                return (
                  <div key={worker.id} className="flex items-center gap-3 px-4 py-3 border-b border-gray-50 last:border-0">
                    <div className="flex-1 min-w-0">
                      <button
                        onClick={() => setViewUserId(worker.id)}
                        className="text-sm font-medium text-gray-800 hover:text-orange-600 transition-colors text-left"
                      >
                        {worker.name}
                      </button>
                      <div className="text-[11px] text-gray-400">
                        {worker.dayRate ? `£${worker.dayRate}/day` : 'No rate set'}
                        {wDays > 0 && ` · ${wDays} ${wDays === 1 ? 'day' : 'days'} this week`}
                      </div>
                    </div>
                    {wDays > 0 && (
                      <div className="text-right shrink-0 mr-1">
                        <div className="text-xs text-gray-500">£{wGross.toFixed(0)} gross</div>
                        <div className="text-sm font-bold text-green-700">£{wNet.toFixed(0)} net</div>
                      </div>
                    )}
                    <button
                      onClick={() => { if (window.confirm(`Remove ${worker.name} and their timesheet entries?`)) removeCasualWorker(worker.id); }}
                      className="text-gray-300 hover:text-red-500 shrink-0 transition-colors"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                );
              })
            )}
          </div>
        )}

        </> /* end tab === 'timesheet' */}
      </div>

      {showProfile && viewUser && (
        <ProfileModal user={viewUser} onClose={() => setShowProfile(false)} />
      )}

      {showAddCasual && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4" style={{ background: 'rgba(0,0,0,0.5)' }}>
          <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md">
            <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
              <h2 className="text-base font-semibold text-gray-900">Add Casual Worker</h2>
              <button onClick={() => setShowAddCasual(false)} className="text-gray-400 hover:text-gray-600"><X size={18} /></button>
            </div>
            <div className="p-5 space-y-4">
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Name</label>
                <input
                  type="text" value={casualName}
                  onChange={e => setCasualName(e.target.value)}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500"
                  placeholder="e.g. Dave Smith"
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-500 mb-1">Day Rate (£ gross)</label>
                  <input
                    type="number" min="0" step="1" value={casualDayRate}
                    onChange={e => setCasualDayRate(e.target.value)}
                    className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500"
                    placeholder="e.g. 150"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-500 mb-1">CIS Deduction Rate</label>
                  <div className="flex rounded-lg overflow-hidden border border-gray-200 h-[38px]">
                    <button type="button" onClick={() => setCasualCisRate(20)} className={`flex-1 text-sm font-medium transition-colors ${casualCisRate === 20 ? 'bg-orange-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>20%</button>
                    <button type="button" onClick={() => setCasualCisRate(30)} className={`flex-1 text-sm font-medium transition-colors ${casualCisRate === 30 ? 'bg-orange-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>30%</button>
                  </div>
                </div>
              </div>
              {casualName && casualDayRate && (
                <div className="bg-gray-50 rounded-xl px-4 py-3 flex justify-between text-sm">
                  <div className="space-y-0.5">
                    <div className="text-gray-500">Gross (full day)</div>
                    <div className="text-gray-500">CIS ({casualCisRate}%)</div>
                    <div className="font-semibold text-gray-800">Net take-home</div>
                  </div>
                  <div className="space-y-0.5 text-right">
                    <div className="text-gray-700">£{parseFloat(casualDayRate || '0').toFixed(0)}</div>
                    <div className="text-red-500">−£{(parseFloat(casualDayRate || '0') * casualCisRate / 100).toFixed(0)}</div>
                    <div className="font-semibold text-green-700">£{(parseFloat(casualDayRate || '0') * (1 - casualCisRate / 100)).toFixed(0)}</div>
                  </div>
                </div>
              )}
            </div>
            <div className="flex gap-3 px-5 py-4 border-t border-gray-100">
              <button onClick={() => setShowAddCasual(false)} className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2 rounded-xl hover:bg-gray-50 transition-colors">
                Cancel
              </button>
              <button
                onClick={saveCasualWorker}
                disabled={!casualName.trim() || !casualDayRate}
                className="flex-1 bg-orange-600 text-white text-sm font-medium py-2 rounded-xl hover:bg-orange-700 disabled:opacity-40 transition-colors"
              >
                Add Worker
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

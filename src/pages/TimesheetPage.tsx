import { useState, useMemo, useRef, useEffect } from 'react';
import {
  ChevronLeft, ChevronRight, Clock, Pencil, X, Trash2, UserPlus,
  Banknote, CalendarCheck, CheckCircle2, Printer, FileText, ChevronDown, ChevronUp,
} from 'lucide-react';
import { useStore } from '../store/useStore';
import { formatCurrency } from '../utils/helpers';
import type { AppUser, TimesheetEntry, PaymentRun } from '../types';

// ── Date helpers ─────────────────────────────────────────────────────────────

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

function fmtRange(mon: Date): string {
  const sun = addDays(mon, 6);
  return `${mon.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })} – ${sun.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}`;
}

// ── Add / Edit Day Modal ──────────────────────────────────────────────────────

interface AddDayModalProps {
  date: string;
  userId: string;
  userName: string;
  existingEntry?: TimesheetEntry;
  dayRate: number;
  cisRate: number;
  leads: { id: string; name: string; jobRef: string }[];
  onSave: (leadId: string, type: 'full' | 'half', amount: number) => void;
  onDelete?: () => void;
  onClose: () => void;
}

function AddDayModal({ date, userName, existingEntry, dayRate, cisRate, leads, onSave, onDelete, onClose }: AddDayModalProps) {
  const [leadId, setLeadId] = useState(existingEntry?.leadId ?? '');
  const [type, setType] = useState<'full' | 'half'>(existingEntry?.type ?? 'full');

  const gross = dayRate * (type === 'full' ? 1 : 0.5);
  const net = gross * (1 - cisRate / 100);

  const d = new Date(date + 'T00:00:00');
  const dateLabel = d.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' });

  const save = () => {
    if (!leadId) return;
    onSave(leadId, type, gross);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4" style={{ background: 'rgba(0,0,0,0.5)' }}>
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-sm">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <div>
            <h2 className="text-sm font-bold text-gray-900">{existingEntry ? 'Edit Day' : 'Log Day'}</h2>
            <p className="text-xs text-gray-400">{userName} · {dateLabel}</p>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600"><X size={18} /></button>
        </div>
        <div className="p-5 space-y-4">
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1.5">Job / Site</label>
            <select
              value={leadId} onChange={e => setLeadId(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-orange-500"
            >
              <option value="">Select a job…</option>
              {leads.map(l => (
                <option key={l.id} value={l.id}>{l.jobRef ? `${l.jobRef} – ` : ''}{l.name}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1.5">Day type</label>
            <div className="flex rounded-xl overflow-hidden border border-gray-200">
              <button type="button" onClick={() => setType('full')}
                className={`flex-1 py-2.5 text-sm font-semibold transition-colors ${type === 'full' ? 'bg-orange-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>
                Full day
              </button>
              <button type="button" onClick={() => setType('half')}
                className={`flex-1 py-2.5 text-sm font-semibold transition-colors ${type === 'half' ? 'bg-orange-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>
                Half day
              </button>
            </div>
          </div>

          {dayRate > 0 && (
            <div className="bg-gray-50 rounded-xl px-4 py-3 flex justify-between items-center">
              <div className="space-y-0.5">
                <div className="text-xs text-gray-500">Gross pay</div>
                <div className="text-xs text-red-400">CIS {cisRate}% deduction</div>
                <div className="text-xs font-bold text-green-700">Net take-home</div>
              </div>
              <div className="space-y-0.5 text-right">
                <div className="text-sm font-semibold text-gray-700">£{gross.toFixed(0)}</div>
                <div className="text-sm text-red-400">−£{(gross * cisRate / 100).toFixed(0)}</div>
                <div className="text-sm font-bold text-green-700">£{net.toFixed(0)}</div>
              </div>
            </div>
          )}
        </div>
        <div className="flex gap-2 px-5 py-4 border-t border-gray-100">
          {onDelete && (
            <button onClick={() => { onDelete(); onClose(); }}
              className="p-2.5 rounded-xl border border-gray-200 text-gray-400 hover:text-red-500 hover:border-red-200 transition-colors">
              <Trash2 size={15} />
            </button>
          )}
          <button onClick={onClose} className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50 transition-colors">
            Cancel
          </button>
          <button onClick={save} disabled={!leadId || dayRate === 0}
            className="flex-1 bg-orange-600 text-white text-sm font-semibold py-2.5 rounded-xl hover:bg-orange-700 disabled:opacity-40 transition-colors">
            {existingEntry ? 'Save changes' : 'Log day'}
          </button>
        </div>
        {dayRate === 0 && (
          <p className="px-5 pb-4 text-xs text-amber-600 text-center">Set a day rate in Edit Details to log time.</p>
        )}
      </div>
    </div>
  );
}

// ── Profile edit modal ────────────────────────────────────────────────────────

function ProfileModal({ user, onClose }: { user: AppUser; onClose: () => void }) {
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

  const net = dayRate ? parseFloat(dayRate) * (1 - cisRate / 100) : 0;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4" style={{ background: 'rgba(0,0,0,0.5)' }}>
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h2 className="text-base font-semibold text-gray-900">Payment Details — {user.name}</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600"><X size={18} /></button>
        </div>
        <div className="p-5 space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">Day Rate (£ gross)</label>
              <input type="number" min="0" step="0.01" value={dayRate} onChange={e => setDayRate(e.target.value)}
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500" placeholder="e.g. 250" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">CIS Deduction Rate</label>
              <div className="flex rounded-xl overflow-hidden border border-gray-200 h-[38px]">
                <button type="button" onClick={() => setCisRate(20)} className={`flex-1 text-sm font-semibold transition-colors ${cisRate === 20 ? 'bg-orange-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>20%</button>
                <button type="button" onClick={() => setCisRate(30)} className={`flex-1 text-sm font-semibold transition-colors ${cisRate === 30 ? 'bg-orange-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>30%</button>
              </div>
            </div>
          </div>
          {dayRate && (
            <div className="bg-gray-50 rounded-xl px-4 py-3 flex justify-between text-sm">
              <div className="space-y-0.5 text-gray-500">
                <div>Gross (full day)</div><div>CIS ({cisRate}%)</div>
                <div className="font-semibold text-gray-800">Net take-home</div>
              </div>
              <div className="space-y-0.5 text-right">
                <div className="text-gray-700">£{parseFloat(dayRate).toFixed(0)}</div>
                <div className="text-red-500">−£{(parseFloat(dayRate) * cisRate / 100).toFixed(0)}</div>
                <div className="font-semibold text-green-700">£{net.toFixed(0)}</div>
              </div>
            </div>
          )}
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">UTR Number</label>
            <input type="text" value={utr} onChange={e => setUtr(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500" placeholder="e.g. 1234567890" />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">Bank Name</label>
            <input type="text" value={bank} onChange={e => setBank(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500" placeholder="e.g. Barclays" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">Account Number</label>
              <input type="text" value={account} onChange={e => setAccount(e.target.value)}
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500" placeholder="12345678" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">Sort Code</label>
              <input type="text" value={sortCode} onChange={e => setSortCode(e.target.value)}
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500" placeholder="12-34-56" />
            </div>
          </div>
        </div>
        <div className="flex gap-3 px-5 py-4 border-t border-gray-100">
          <button onClick={onClose} className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50 transition-colors">Cancel</button>
          <button onClick={save} className="flex-1 bg-orange-600 text-white text-sm font-semibold py-2.5 rounded-xl hover:bg-orange-700 transition-colors">Save</button>
        </div>
      </div>
    </div>
  );
}

// ── Rota grid ─────────────────────────────────────────────────────────────────

interface RotaProps {
  workers: AppUser[];
  isCasual?: boolean;
  weekDays: { date: string; dayLabel: string; numLabel: string }[];
  entries: TimesheetEntry[];
  leads: { id: string; name: string; jobRef: string }[];
  canEditAll: boolean;
  currentUserId: string;
  onCellClick: (userId: string, date: string, existing?: TimesheetEntry) => void;
  onEditProfile: (user: AppUser) => void;
  onRemoveCasual?: (user: AppUser) => void;
}

function RotaSection({ workers, isCasual, weekDays, entries, leads, canEditAll, currentUserId, onCellClick, onEditProfile, onRemoveCasual }: RotaProps) {
  const today = toYMD(new Date());

  if (workers.length === 0 && isCasual) return null;

  return (
    <>
      {isCasual && (
        <tr>
          <td colSpan={weekDays.length + 2} className="px-3 py-1.5 bg-gray-50 border-y border-gray-100">
            <span className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">Casual / Subcontractors</span>
          </td>
        </tr>
      )}
      {workers.map(worker => {
        const workerEntries = entries.filter(e => e.userId === worker.id);
        const days = workerEntries.reduce((s, e) => s + (e.type === 'full' ? 1 : 0.5), 0);
        const gross = workerEntries.reduce((s, e) => s + e.amount, 0);
        const net = gross * (1 - (worker.cisRate ?? 20) / 100);
        const canEdit = canEditAll || worker.id === currentUserId;

        return (
          <tr key={worker.id} className="hover:bg-orange-50/30 transition-colors group">
            {/* Worker name */}
            <td className="px-3 py-2.5 border-b border-gray-50 min-w-[120px] max-w-[150px]">
              <div className="flex items-center gap-2">
                <div className="w-7 h-7 rounded-lg bg-orange-100 flex items-center justify-center text-orange-700 font-bold text-xs shrink-0">
                  {worker.name.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase()}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="text-xs font-semibold text-gray-800 truncate">{worker.name}</div>
                  <div className="text-[10px] text-gray-400">
                    {days > 0 ? `${days}d · £${net.toFixed(0)} net` : (worker.dayRate ? `£${worker.dayRate}/day` : 'No rate')}
                  </div>
                </div>
              </div>
            </td>

            {/* Day cells */}
            {weekDays.map(({ date }) => {
              const entry = workerEntries.find(e => e.date === date);
              const isWeekend = (() => { const d = new Date(date + 'T00:00:00'); return d.getDay() === 0 || d.getDay() === 6; })();
              const isPast = date <= today;
              const isToday = date === today;

              return (
                <td key={date}
                  className={`border-b border-gray-50 text-center py-2 px-1 ${isWeekend ? 'bg-gray-50/50' : ''}`}
                  style={{ width: 44 }}
                >
                  {entry ? (
                    <button
                      onClick={() => canEdit && onCellClick(worker.id, date, entry)}
                      className={`mx-auto w-8 h-8 rounded-lg flex items-center justify-center text-xs font-bold transition-all
                        ${entry.type === 'full'
                          ? 'bg-orange-500 text-white hover:bg-orange-600'
                          : 'bg-amber-400 text-white hover:bg-amber-500'}
                        ${!canEdit ? 'cursor-default' : 'cursor-pointer'}`}
                      title={leads.find(l => l.id === entry.leadId)?.name ?? ''}
                    >
                      {entry.type === 'full' ? 'F' : 'H'}
                    </button>
                  ) : (
                    canEdit && isPast && !isWeekend ? (
                      <button
                        onClick={() => onCellClick(worker.id, date)}
                        className={`mx-auto w-8 h-8 rounded-lg flex items-center justify-center text-gray-300 hover:text-orange-500 hover:bg-orange-50 transition-all ${isToday ? 'ring-2 ring-orange-300 ring-offset-1' : ''}`}
                      >
                        <span className="text-lg leading-none">+</span>
                      </button>
                    ) : (
                      <span className="text-gray-200 text-sm select-none">{isPast ? '–' : ''}</span>
                    )
                  )}
                </td>
              );
            })}

            {/* Actions */}
            <td className="border-b border-gray-50 px-2 py-2.5">
              <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                {(canEditAll || worker.id === currentUserId) && (
                  <button onClick={() => onEditProfile(worker)}
                    className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-400 hover:text-gray-600" title="Edit details">
                    <Pencil size={12} />
                  </button>
                )}
                {isCasual && canEditAll && onRemoveCasual && (
                  <button onClick={() => onRemoveCasual(worker)}
                    className="p-1.5 rounded-lg hover:bg-red-50 text-gray-300 hover:text-red-500" title="Remove worker">
                    <Trash2 size={12} />
                  </button>
                )}
              </div>
            </td>
          </tr>
        );
      })}
    </>
  );
}

// ── Payments tab ──────────────────────────────────────────────────────────────

const STATUS_META: Record<string, { label: string; pill: string; icon: React.ReactNode }> = {
  due:       { label: 'Due',       pill: 'bg-amber-100 text-amber-700 border-amber-200',  icon: <Clock size={11} /> },
  scheduled: { label: 'Scheduled', pill: 'bg-blue-100 text-blue-700 border-blue-200',     icon: <CalendarCheck size={11} /> },
  paid:      { label: 'Paid',      pill: 'bg-green-100 text-green-700 border-green-200',  icon: <CheckCircle2 size={11} /> },
};

type PayFilter = 'all' | 'due' | 'scheduled' | 'paid';

function PaymentsTab({ users, timesheetEntries, paymentRuns, updatePaymentStatus }: {
  users: AppUser[];
  timesheetEntries: TimesheetEntry[];
  paymentRuns: PaymentRun[];
  updatePaymentStatus: (userId: string, weekStart: string, status: PaymentRun['status']) => void;
}) {
  const [filter, setFilter] = useState<PayFilter>('all');

  const summaries = useMemo(() => {
    const map = new Map<string, { userId: string; weekStart: string; entries: TimesheetEntry[] }>();
    for (const entry of timesheetEntries) {
      const ws = toYMD(getMonday(new Date(entry.date + 'T00:00:00')));
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
      const status = (run?.status ?? 'due') as PaymentRun['status'];
      const mon = new Date(weekStart + 'T00:00:00');
      const weekLabel = fmtRange(mon);
      return { userId, weekStart, user, days, gross, net, rate, status, paidDate: run?.paidDate, weekLabel };
    }).sort((a, b) => b.weekStart.localeCompare(a.weekStart) || (a.user?.name ?? '').localeCompare(b.user?.name ?? ''));
  }, [users, timesheetEntries, paymentRuns]);

  const filtered = filter === 'all' ? summaries : summaries.filter(s => s.status === filter);
  const totals = {
    due:       summaries.filter(s => s.status === 'due').reduce((t, s) => t + s.net, 0),
    scheduled: summaries.filter(s => s.status === 'scheduled').reduce((t, s) => t + s.net, 0),
    paid:      summaries.filter(s => s.status === 'paid').reduce((t, s) => t + s.net, 0),
  };

  return (
    <div className="space-y-4">
      {/* Summary cards */}
      <div className="grid grid-cols-3 gap-3">
        {(['due', 'scheduled', 'paid'] as const).map(s => (
          <button key={s} onClick={() => setFilter(f => f === s ? 'all' : s)}
            className={`rounded-2xl p-3 text-center border transition-all ${filter === s ? 'ring-2 ring-orange-500' : ''}
              ${s === 'due' ? 'bg-amber-50 border-amber-100' : s === 'scheduled' ? 'bg-blue-50 border-blue-100' : 'bg-green-50 border-green-100'}`}>
            <div className={`text-[10px] font-bold uppercase tracking-wide mb-1 ${s === 'due' ? 'text-amber-600' : s === 'scheduled' ? 'text-blue-600' : 'text-green-700'}`}>
              {STATUS_META[s].label}
            </div>
            <div className={`text-lg font-bold ${s === 'due' ? 'text-amber-700' : s === 'scheduled' ? 'text-blue-700' : 'text-green-700'}`}>
              £{totals[s].toFixed(0)}
            </div>
            <div className="text-[10px] text-gray-400 mt-0.5">
              {summaries.filter(x => x.status === s).length} payment{summaries.filter(x => x.status === s).length !== 1 ? 's' : ''}
            </div>
          </button>
        ))}
      </div>

      {/* Filter pills */}
      <div className="flex gap-1.5 flex-wrap">
        {(['all', 'due', 'scheduled', 'paid'] as PayFilter[]).map(f => (
          <button key={f} onClick={() => setFilter(f)}
            className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors ${filter === f ? 'bg-orange-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
            {f === 'all' ? `All (${summaries.length})` : `${STATUS_META[f].label} (${summaries.filter(s => s.status === f).length})`}
          </button>
        ))}
      </div>

      {/* Rows */}
      {filtered.length === 0 ? (
        <div className="bg-white rounded-2xl border border-gray-100 p-10 text-center">
          <Banknote size={32} className="mx-auto text-gray-200 mb-2" />
          <p className="text-sm text-gray-400">No payments to show</p>
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
                <div className="w-9 h-9 rounded-xl bg-orange-100 flex items-center justify-center text-orange-700 font-bold text-sm shrink-0">
                  {initials}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="text-sm font-semibold text-gray-800">{s.user?.name ?? 'Unknown'}</div>
                  <div className="text-[11px] text-gray-400">{s.weekLabel}</div>
                  <div className="text-[11px] text-gray-400">{s.days} {s.days === 1 ? 'day' : 'days'}</div>
                </div>
                <div className="text-right shrink-0 mr-1 hidden sm:block">
                  <div className="text-xs text-gray-400">£{s.gross.toFixed(0)} gross</div>
                  <div className="text-xs text-red-400">−£{(s.gross - s.net).toFixed(0)} CIS {s.rate}%</div>
                  <div className="text-sm font-bold text-gray-800">£{s.net.toFixed(0)} net</div>
                </div>
                <div className="shrink-0 flex flex-col items-end gap-1.5 min-w-[90px]">
                  <span className={`inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full border ${meta.pill}`}>
                    {meta.icon}{meta.label}
                  </span>
                  {s.status === 'due' && (
                    <button onClick={() => updatePaymentStatus(s.userId, s.weekStart, 'scheduled')}
                      className="text-[11px] font-semibold text-blue-600 hover:text-blue-800 bg-blue-50 hover:bg-blue-100 px-2 py-0.5 rounded-md transition-colors">
                      Schedule
                    </button>
                  )}
                  {s.status === 'scheduled' && (
                    <button onClick={() => updatePaymentStatus(s.userId, s.weekStart, 'paid')}
                      className="text-[11px] font-semibold text-green-600 hover:text-green-800 bg-green-50 hover:bg-green-100 px-2 py-0.5 rounded-md transition-colors">
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

// ── CIS tab ───────────────────────────────────────────────────────────────────

const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December'];

function formatDateStr(s: string) {
  const [y, m, d] = s.split('-');
  return `${d}/${m}/${y}`;
}

type WorkerRow = { user: AppUser; entries: TimesheetEntry[]; gross: number; cisRate: 20 | 30; deduction: number; net: number };

function buildStatementHtml(row: WorkerRow, leads: { id: string; address: string }[], month: number, year: number) {
  const { user, entries, cisRate, gross, deduction, net } = row;
  const entryRows = entries.map(e => {
    const lead = leads.find(l => l.id === e.leadId);
    const ded = Math.round(e.amount * cisRate) / 100;
    return `<tr><td>${formatDateStr(e.date)}</td><td>${lead?.address ?? '—'}</td><td>${e.type === 'full' ? 'Full Day' : 'Half Day'}</td>
    <td style="text-align:right">£${e.amount.toFixed(2)}</td><td style="text-align:right;color:#dc2626">-£${ded.toFixed(2)}</td>
    <td style="text-align:right;color:#16a34a;font-weight:bold">£${(e.amount - ded).toFixed(2)}</td></tr>`;
  }).join('');
  return `<!DOCTYPE html><html><head><title>CIS Statement – ${user.name}</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:Arial,sans-serif;padding:40px;font-size:13px;color:#1f2937}
.hdr{display:flex;justify-content:space-between;margin-bottom:28px}.title{font-size:22px;font-weight:bold}
.info{display:grid;grid-template-columns:1fr 1fr;background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;padding:16px;margin-bottom:24px}
.info-item{padding:6px 12px}.info-item label{display:block;font-size:10px;text-transform:uppercase;color:#9ca3af;margin-bottom:3px}
.info-item span{font-weight:700;font-size:14px}table{width:100%;border-collapse:collapse;margin-bottom:20px}
thead tr{background:#1f2937;color:white}th{padding:10px 12px;text-align:left;font-size:11px;text-transform:uppercase}
td{padding:10px 12px;border-bottom:1px solid #f3f4f6}.tot{background:#1f2937;color:white;font-weight:bold}.tot td{color:white;border:none}
.footer{margin-top:24px;font-size:11px;color:#9ca3af;border-top:1px solid #e5e7eb;padding-top:12px;line-height:1.7}
</style></head><body>
<div class="hdr"><div><div class="title">CIS Payment Statement</div><div style="color:#6b7280">${MONTHS[month]} ${year}</div></div>
<div style="text-align:right;font-size:11px;color:#9ca3af"><div style="font-weight:bold;font-size:13px;color:#1f2937">ProLine Roofing &amp; Solar</div><div>Issued: ${new Date().toLocaleDateString('en-GB')}</div></div></div>
<div class="info">
<div class="info-item"><label>Subcontractor</label><span>${user.name}</span></div>
<div class="info-item"><label>UTR Number</label><span>${user.utrNumber ?? 'Not provided'}</span></div>
<div class="info-item"><label>CIS Deduction Rate</label><span>${cisRate}%</span></div>
<div class="info-item"><label>Day Rate</label><span>£${user.dayRate?.toFixed(2) ?? '0.00'}</span></div></div>
<table><thead><tr><th>Date</th><th>Job Site</th><th>Type</th><th style="text-align:right">Gross</th><th style="text-align:right">CIS (${cisRate}%)</th><th style="text-align:right">Net Pay</th></tr></thead>
<tbody>${entryRows}<tr class="tot"><td colspan="3">TOTAL</td><td style="text-align:right">£${gross.toFixed(2)}</td><td style="text-align:right">-£${deduction.toFixed(2)}</td><td style="text-align:right">£${net.toFixed(2)}</td></tr></tbody></table>
<div class="footer">This statement is issued under the Construction Industry Scheme (CIS) as required by HMRC. The CIS deduction of £${deduction.toFixed(2)} has been withheld and will be paid to HMRC on your behalf.</div>
<script>window.onload=()=>window.print()</script></body></html>`;
}

function buildReturnHtml(rows: WorkerRow[], totalGross: number, totalDeduction: number, totalNet: number, month: number, year: number) {
  const rowsHtml = rows.map(r => `<tr><td>${r.user.name}</td><td style="font-family:monospace">${r.user.utrNumber ?? '—'}</td>
<td style="text-align:center">${r.entries.length}</td><td style="text-align:right">£${r.gross.toFixed(2)}</td>
<td style="text-align:center">${r.cisRate}%</td><td style="text-align:right;color:#dc2626">-£${r.deduction.toFixed(2)}</td>
<td style="text-align:right;color:#16a34a;font-weight:bold">£${r.net.toFixed(2)}</td></tr>`).join('');
  return `<!DOCTYPE html><html><head><title>CIS Monthly Return – ${MONTHS[month]} ${year}</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:Arial,sans-serif;padding:40px;font-size:13px;color:#1f2937}
.hdr{display:flex;justify-content:space-between;margin-bottom:28px}.title{font-size:22px;font-weight:bold}
table{width:100%;border-collapse:collapse;margin-top:16px}thead tr{background:#1f2937;color:white}
th{padding:10px 12px;text-align:left;font-size:11px;text-transform:uppercase}td{padding:10px 12px;border-bottom:1px solid #f3f4f6}
.tot{background:#1f2937;color:white;font-weight:bold}.tot td{color:white;border:none}
.notice{margin-top:24px;font-size:11px;color:#9ca3af;border-top:1px solid #e5e7eb;padding-top:12px;line-height:1.7}
</style></head><body>
<div class="hdr"><div><div class="title">CIS Monthly Return</div><div style="color:#6b7280">${MONTHS[month]} ${year}</div></div>
<div style="text-align:right;font-size:11px;color:#9ca3af"><div style="font-weight:bold;font-size:13px;color:#1f2937">ProLine Roofing &amp; Solar</div><div>Printed: ${new Date().toLocaleDateString('en-GB')}</div></div></div>
<table><thead><tr><th>Subcontractor</th><th>UTR Number</th><th style="text-align:center">Days</th><th style="text-align:right">Gross Paid</th><th style="text-align:center">Rate</th><th style="text-align:right">CIS Deducted</th><th style="text-align:right">Net Paid</th></tr></thead>
<tbody>${rowsHtml}<tr class="tot"><td colspan="3">TOTAL — ${rows.length} subcontractor${rows.length !== 1 ? 's' : ''}</td>
<td style="text-align:right">£${totalGross.toFixed(2)}</td><td></td><td style="text-align:right">-£${totalDeduction.toFixed(2)}</td><td style="text-align:right">£${totalNet.toFixed(2)}</td></tr></tbody></table>
<div class="notice">Use these figures when submitting your CIS Monthly Return to HMRC via the Government Gateway. File by the 19th of the following month.</div>
<script>window.onload=()=>window.print()</script></body></html>`;
}

function openPrint(html: string) {
  const w = window.open('', '_blank', 'width=900,height=700');
  if (w) { w.document.write(html); w.document.close(); }
}

function CISTab({ timesheetEntries, users, leads }: { timesheetEntries: TimesheetEntry[]; users: AppUser[]; leads: { id: string; address: string }[] }) {
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth());
  const [expanded, setExpanded] = useState<string | null>(null);
  const years = [now.getFullYear() - 1, now.getFullYear(), now.getFullYear() + 1];

  const monthEntries = timesheetEntries.filter(e => {
    const [y, m] = e.date.split('-').map(Number);
    return y === year && m - 1 === month;
  });

  const workerIds = [...new Set(monthEntries.map(e => e.userId))];
  const rows: WorkerRow[] = workerIds.map(uid => {
    const user = users.find(u => u.id === uid);
    if (!user) return null;
    const entries = monthEntries.filter(e => e.userId === uid).sort((a, b) => a.date.localeCompare(b.date));
    const gross = entries.reduce((s, e) => s + e.amount, 0);
    const cisRate = (user.cisRate ?? 20) as 20 | 30;
    const deduction = Math.round(gross * cisRate) / 100;
    return { user, entries, gross, cisRate, deduction, net: gross - deduction };
  }).filter((r): r is WorkerRow => r !== null);

  const totalGross = rows.reduce((s, r) => s + r.gross, 0);
  const totalDeduction = rows.reduce((s, r) => s + r.deduction, 0);
  const totalNet = rows.reduce((s, r) => s + r.net, 0);

  return (
    <div className="space-y-4">
      {/* Controls */}
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div className="flex items-center gap-2">
          <select value={month} onChange={e => setMonth(Number(e.target.value))}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500 bg-white">
            {MONTHS.map((m, i) => <option key={m} value={i}>{m}</option>)}
          </select>
          <select value={year} onChange={e => setYear(Number(e.target.value))}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500 bg-white">
            {years.map(y => <option key={y} value={y}>{y}</option>)}
          </select>
        </div>
        {rows.length > 0 && (
          <button onClick={() => openPrint(buildReturnHtml(rows, totalGross, totalDeduction, totalNet, month, year))}
            className="flex items-center gap-1.5 bg-orange-600 text-white px-4 py-2 rounded-xl text-sm font-semibold hover:bg-orange-700">
            <Printer size={14} /> Print Return
          </button>
        )}
      </div>

      {/* Totals */}
      {rows.length > 0 && (
        <div className="grid grid-cols-3 gap-3">
          <div className="bg-gray-50 rounded-2xl p-4"><p className="text-[10px] font-bold text-gray-400 uppercase tracking-wide mb-1">Total Gross</p><p className="text-xl font-bold text-gray-800">{formatCurrency(totalGross)}</p></div>
          <div className="bg-red-50 rounded-2xl p-4"><p className="text-[10px] font-bold text-red-400 uppercase tracking-wide mb-1">CIS Deducted</p><p className="text-xl font-bold text-red-600">{formatCurrency(totalDeduction)}</p></div>
          <div className="bg-green-50 rounded-2xl p-4"><p className="text-[10px] font-bold text-green-600 uppercase tracking-wide mb-1">Net Paid Out</p><p className="text-xl font-bold text-green-700">{formatCurrency(totalNet)}</p></div>
        </div>
      )}

      {/* Worker rows */}
      {rows.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-gray-300">
          <FileText size={40} className="mb-3" />
          <p className="font-semibold text-gray-400">No entries for {MONTHS[month]} {year}</p>
        </div>
      ) : (
        <div className="space-y-2">
          {rows.map(row => (
            <div key={row.user.id} className="border border-gray-100 rounded-2xl overflow-hidden shadow-sm">
              <div className="flex items-center gap-3 px-4 py-3 bg-white">
                <div className="w-9 h-9 rounded-xl bg-orange-100 flex items-center justify-center text-orange-700 font-bold text-sm shrink-0">
                  {row.user.name[0]}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-gray-800 text-sm">{row.user.name}</p>
                  <p className="text-xs text-gray-400">
                    UTR: {row.user.utrNumber ?? <span className="text-amber-500">Not set</span>}
                    {' · '}CIS {row.cisRate}%{' · '}{row.entries.length} day{row.entries.length !== 1 ? 's' : ''}
                  </p>
                </div>
                <div className="hidden sm:flex items-center gap-5 text-right shrink-0">
                  <div><p className="text-[10px] text-gray-400 uppercase font-semibold">Gross</p><p className="text-sm font-bold text-gray-800">{formatCurrency(row.gross)}</p></div>
                  <div><p className="text-[10px] text-red-400 uppercase font-semibold">CIS</p><p className="text-sm font-bold text-red-600">-{formatCurrency(row.deduction)}</p></div>
                  <div><p className="text-[10px] text-green-600 uppercase font-semibold">Net</p><p className="text-sm font-bold text-green-700">{formatCurrency(row.net)}</p></div>
                </div>
                <div className="flex items-center gap-1.5 shrink-0">
                  <button onClick={() => openPrint(buildStatementHtml(row, leads, month, year))}
                    className="flex items-center gap-1 text-xs bg-gray-100 hover:bg-gray-200 text-gray-600 px-2.5 py-1.5 rounded-lg font-medium">
                    <Printer size={12} /> Statement
                  </button>
                  <button onClick={() => setExpanded(expanded === row.user.id ? null : row.user.id)}
                    className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-400">
                    {expanded === row.user.id ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
                  </button>
                </div>
              </div>
              {expanded === row.user.id && (
                <div className="border-t border-gray-100">
                  <table className="w-full text-sm">
                    <thead className="bg-gray-50">
                      <tr>
                        <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</th>
                        <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide hidden sm:table-cell">Job Site</th>
                        <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Type</th>
                        <th className="text-right px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Gross</th>
                        <th className="text-right px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide hidden sm:table-cell">CIS</th>
                        <th className="text-right px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Net</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-50">
                      {row.entries.map(entry => {
                        const lead = leads.find(l => l.id === entry.leadId);
                        const ded = Math.round(entry.amount * row.cisRate) / 100;
                        return (
                          <tr key={entry.id} className="hover:bg-gray-50">
                            <td className="px-4 py-2.5 text-gray-700 whitespace-nowrap">{formatDateStr(entry.date)}</td>
                            <td className="px-4 py-2.5 text-gray-500 text-xs hidden sm:table-cell truncate max-w-[200px]">{lead?.address ?? '—'}</td>
                            <td className="px-4 py-2.5">
                              <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${entry.type === 'full' ? 'bg-orange-100 text-orange-700' : 'bg-gray-100 text-gray-600'}`}>
                                {entry.type === 'full' ? 'Full' : 'Half'}
                              </span>
                            </td>
                            <td className="px-4 py-2.5 text-right font-medium text-gray-800">{formatCurrency(entry.amount)}</td>
                            <td className="px-4 py-2.5 text-right text-red-500 hidden sm:table-cell">-{formatCurrency(ded)}</td>
                            <td className="px-4 py-2.5 text-right font-semibold text-green-700">{formatCurrency(entry.amount - ded)}</td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Add Casual Modal ──────────────────────────────────────────────────────────

function AddCasualModal({ onSave, onClose }: { onSave: (name: string, rate: number, cis: 20|30) => void; onClose: () => void }) {
  const [name, setName] = useState('');
  const [rate, setRate] = useState('');
  const [cis, setCis] = useState<20|30>(20);
  const net = rate ? parseFloat(rate) * (1 - cis / 100) : 0;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4" style={{ background: 'rgba(0,0,0,0.5)' }}>
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h2 className="text-base font-semibold text-gray-900">Add Casual Worker</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600"><X size={18} /></button>
        </div>
        <div className="p-5 space-y-4">
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">Name</label>
            <input type="text" value={name} onChange={e => setName(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500" placeholder="e.g. Dave Smith" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">Day Rate (£ gross)</label>
              <input type="number" min="0" step="1" value={rate} onChange={e => setRate(e.target.value)}
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500" placeholder="e.g. 150" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">CIS Rate</label>
              <div className="flex rounded-xl overflow-hidden border border-gray-200 h-[38px]">
                <button type="button" onClick={() => setCis(20)} className={`flex-1 text-sm font-semibold transition-colors ${cis === 20 ? 'bg-orange-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>20%</button>
                <button type="button" onClick={() => setCis(30)} className={`flex-1 text-sm font-semibold transition-colors ${cis === 30 ? 'bg-orange-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>30%</button>
              </div>
            </div>
          </div>
          {name && rate && (
            <div className="bg-gray-50 rounded-xl px-4 py-3 flex justify-between text-sm">
              <div className="space-y-0.5 text-gray-500"><div>Gross (full day)</div><div>CIS ({cis}%)</div><div className="font-semibold text-gray-800">Net take-home</div></div>
              <div className="space-y-0.5 text-right"><div className="text-gray-700">£{parseFloat(rate).toFixed(0)}</div><div className="text-red-500">−£{(parseFloat(rate) * cis / 100).toFixed(0)}</div><div className="font-semibold text-green-700">£{net.toFixed(0)}</div></div>
            </div>
          )}
        </div>
        <div className="flex gap-3 px-5 py-4 border-t border-gray-100">
          <button onClick={onClose} className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50 transition-colors">Cancel</button>
          <button onClick={() => { if (!name.trim() || !rate) return; onSave(name.trim(), parseFloat(rate), cis); onClose(); }}
            disabled={!name.trim() || !rate}
            className="flex-1 bg-orange-600 text-white text-sm font-semibold py-2.5 rounded-xl hover:bg-orange-700 disabled:opacity-40 transition-colors">
            Add Worker
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────────

type Tab = 'rota' | 'payments' | 'cis';

interface CellTarget { userId: string; date: string; existing?: TimesheetEntry }

export default function TimesheetPage() {
  const { users, currentUserId, leads, timesheetEntries, paymentRuns, upsertTimesheetEntry, deleteTimesheetEntry, updatePaymentStatus, addCasualWorker, removeCasualWorker } = useStore();

  const currentUser = users.find(u => u.id === currentUserId)!;
  const isAdmin = currentUser?.role === 'admin';

  const [tab, setTab] = useState<Tab>('rota');
  const [weekStart, setWeekStart] = useState<Date>(() => getMonday(new Date()));
  const [cellTarget, setCellTarget] = useState<CellTarget | null>(null);
  const [profileUser, setProfileUser] = useState<AppUser | null>(null);
  const [showAddCasual, setShowAddCasual] = useState(false);

  const today = toYMD(new Date());
  const todayMon = getMonday(new Date());

  const teamWorkers = useMemo(() => users.filter(u => u.role !== 'casual'), [users]);
  const casualWorkers = useMemo(() => users.filter(u => u.role === 'casual'), [users]);

  const weekDays = useMemo(() => Array.from({ length: 7 }, (_, i) => {
    const d = addDays(weekStart, i);
    return {
      date: toYMD(d),
      dayLabel: d.toLocaleDateString('en-GB', { weekday: 'short' }),
      numLabel: d.toLocaleDateString('en-GB', { day: 'numeric' }),
    };
  }), [weekStart]);

  const weekEntries = useMemo(() =>
    timesheetEntries.filter(e => weekDays.some(d => d.date === e.date)),
    [timesheetEntries, weekDays]
  );

  const isCurrentWeek = toYMD(weekStart) === toYMD(todayMon);

  // Pay summary for the current week view
  const weeklySummary = useMemo(() => {
    const visibleUsers = isAdmin ? users : users.filter(u => u.id === currentUserId);
    return visibleUsers.map(u => {
      const entries = weekEntries.filter(e => e.userId === u.id);
      if (!isAdmin && entries.length === 0 && u.id !== currentUserId) return null;
      const days = entries.reduce((s, e) => s + (e.type === 'full' ? 1 : 0.5), 0);
      const gross = entries.reduce((s, e) => s + e.amount, 0);
      const rate = u.cisRate ?? 20;
      const net = gross * (1 - rate / 100);
      return { user: u, days, gross, net, rate };
    }).filter((r): r is NonNullable<typeof r> => r !== null && r.days > 0);
  }, [users, weekEntries, isAdmin, currentUserId]);

  const activeCell = cellTarget;
  const activeCellUser = activeCell ? users.find(u => u.id === activeCell.userId) : null;

  const tableRef = useRef<HTMLDivElement>(null);

  // Scroll rota table horizontally to show today
  useEffect(() => {
    if (tab === 'rota' && isCurrentWeek && tableRef.current) {
      const todayIdx = weekDays.findIndex(d => d.date === today);
      if (todayIdx >= 0) {
        const table = tableRef.current;
        const colWidth = 44;
        table.scrollLeft = Math.max(0, (todayIdx - 1) * colWidth);
      }
    }
  }, [tab, isCurrentWeek]);

  const tabBtns: { id: Tab; label: string; adminOnly?: boolean }[] = [
    { id: 'rota', label: 'Rota' },
    { id: 'payments', label: 'Payments', adminOnly: true },
    { id: 'cis', label: 'CIS', adminOnly: true },
  ];

  return (
    <div className="h-full overflow-y-auto bg-gray-50">
      <div className="max-w-3xl mx-auto px-4 py-6 space-y-4">

        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl bg-orange-600 flex items-center justify-center shrink-0">
              <Clock size={18} className="text-white" />
            </div>
            <div>
              <h1 className="text-lg font-bold text-gray-900">Timesheet</h1>
              <p className="text-xs text-gray-500">{isAdmin ? 'Team weekly rota' : 'Your weekly hours'}</p>
            </div>
          </div>
        </div>

        {/* Tabs */}
        <div className="flex gap-1 p-1 bg-gray-100 rounded-xl">
          {tabBtns.filter(t => !t.adminOnly || isAdmin).map(t => (
            <button key={t.id} onClick={() => setTab(t.id)}
              className={`flex-1 py-2 text-sm font-semibold rounded-lg transition-colors ${tab === t.id ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}>
              {t.label}
            </button>
          ))}
        </div>

        {/* ── ROTA TAB ── */}
        {tab === 'rota' && (
          <>
            {/* Week nav */}
            <div className="flex items-center justify-between bg-white rounded-2xl border border-gray-100 px-4 py-3">
              <button onClick={() => setWeekStart(d => addDays(d, -7))}
                className="w-8 h-8 flex items-center justify-center rounded-xl hover:bg-gray-100 transition-colors text-gray-500">
                <ChevronLeft size={18} />
              </button>
              <div className="text-center">
                <div className="text-sm font-bold text-gray-800">{fmtRange(weekStart)}</div>
                {!isCurrentWeek && (
                  <button onClick={() => setWeekStart(getMonday(new Date()))}
                    className="text-[11px] text-orange-500 hover:text-orange-700 font-semibold mt-0.5">
                    Back to this week
                  </button>
                )}
              </div>
              <button onClick={() => setWeekStart(d => addDays(d, 7))}
                className="w-8 h-8 flex items-center justify-center rounded-xl hover:bg-gray-100 transition-colors text-gray-500">
                <ChevronRight size={18} />
              </button>
            </div>

            {/* Rota grid */}
            <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
              <div ref={tableRef} className="overflow-x-auto">
                <table className="w-full border-collapse" style={{ minWidth: 500 }}>
                  <thead>
                    <tr className="border-b border-gray-100">
                      <th className="text-left px-3 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide min-w-[130px]">Worker</th>
                      {weekDays.map(({ date, dayLabel, numLabel }) => {
                        const isWeekend = (() => { const d = new Date(date + 'T00:00:00'); return d.getDay() === 0 || d.getDay() === 6; })();
                        const isToday = date === today;
                        return (
                          <th key={date} className={`py-2.5 text-center ${isWeekend ? 'bg-gray-50/50' : ''}`} style={{ width: 44 }}>
                            <div className={`text-[10px] font-semibold uppercase ${isToday ? 'text-orange-600' : isWeekend ? 'text-gray-300' : 'text-gray-400'}`}>{dayLabel}</div>
                            <div className={`text-sm font-bold mt-0.5 ${isToday ? 'text-orange-600' : isWeekend ? 'text-gray-300' : 'text-gray-700'}`}>{numLabel}</div>
                          </th>
                        );
                      })}
                      <th className="w-10" />
                    </tr>
                  </thead>
                  <tbody>
                    <RotaSection
                      workers={isAdmin ? teamWorkers : teamWorkers.filter(u => u.id === currentUserId)}
                      weekDays={weekDays}
                      entries={weekEntries}
                      leads={leads.map(l => ({ id: l.id, name: l.name, jobRef: l.jobRef }))}
                      canEditAll={isAdmin}
                      currentUserId={currentUserId ?? ''}
                      onCellClick={(userId, date, existing) => setCellTarget({ userId, date, existing })}
                      onEditProfile={setProfileUser}
                    />
                    {isAdmin && (
                      <RotaSection
                        workers={casualWorkers}
                        isCasual
                        weekDays={weekDays}
                        entries={weekEntries}
                        leads={leads.map(l => ({ id: l.id, name: l.name, jobRef: l.jobRef }))}
                        canEditAll={isAdmin}
                        currentUserId={currentUserId ?? ''}
                        onCellClick={(userId, date, existing) => setCellTarget({ userId, date, existing })}
                        onEditProfile={setProfileUser}
                        onRemoveCasual={worker => {
                          if (window.confirm(`Remove ${worker.name} and their timesheet entries?`)) removeCasualWorker(worker.id);
                        }}
                      />
                    )}
                    {isAdmin && (
                      <tr>
                        <td colSpan={weekDays.length + 2} className="px-3 py-2 border-t border-gray-50">
                          <button onClick={() => setShowAddCasual(true)}
                            className="flex items-center gap-1.5 text-xs font-semibold text-orange-500 hover:text-orange-700 transition-colors">
                            <UserPlus size={13} /> Add casual worker
                          </button>
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>

              {/* Legend */}
              <div className="flex items-center gap-4 px-4 py-2.5 border-t border-gray-50 bg-gray-50/50">
                <div className="flex items-center gap-1.5">
                  <div className="w-5 h-5 rounded bg-orange-500 flex items-center justify-center text-white text-[10px] font-bold">F</div>
                  <span className="text-[11px] text-gray-500">Full day</span>
                </div>
                <div className="flex items-center gap-1.5">
                  <div className="w-5 h-5 rounded bg-amber-400 flex items-center justify-center text-white text-[10px] font-bold">H</div>
                  <span className="text-[11px] text-gray-500">Half day</span>
                </div>
                <span className="text-[11px] text-gray-400 ml-auto">Click a cell to add or edit</span>
              </div>
            </div>

            {/* Weekly pay summary */}
            {weeklySummary.length > 0 && (
              <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
                <div className="px-4 py-3 border-b border-gray-50 flex items-center justify-between">
                  <h3 className="text-sm font-bold text-gray-800">Week Pay Summary</h3>
                  <span className="text-xs text-gray-400">{fmtRange(weekStart)}</span>
                </div>
                {weeklySummary.map(({ user, days, gross, net, rate }) => (
                  <div key={user.id} className="flex items-center gap-3 px-4 py-3 border-b border-gray-50 last:border-0">
                    <div className="w-8 h-8 rounded-xl bg-orange-100 flex items-center justify-center text-orange-700 font-bold text-xs shrink-0">
                      {user.name.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase()}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-semibold text-gray-800">{user.name}</div>
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
                    <div className="text-right shrink-0">
                      <div className="text-xs text-gray-400">£{gross.toFixed(0)} gross</div>
                      <div className="text-xs text-red-400">−£{(gross * rate / 100).toFixed(0)} CIS {rate}%</div>
                      <div className="text-sm font-bold text-green-700">£{net.toFixed(0)} net</div>
                    </div>
                  </div>
                ))}
                {weeklySummary.length > 1 && (
                  <div className="flex items-center justify-between px-4 py-3 bg-green-50">
                    <div>
                      <div className="text-sm font-bold text-green-800">Total payroll (net)</div>
                      <div className="text-xs text-gray-500">£{weeklySummary.reduce((s, r) => s + r.gross, 0).toFixed(0)} gross</div>
                    </div>
                    <div className="text-xl font-bold text-green-700">
                      £{weeklySummary.reduce((s, r) => s + r.net, 0).toFixed(0)}
                    </div>
                  </div>
                )}
              </div>
            )}
          </>
        )}

        {/* ── PAYMENTS TAB ── */}
        {tab === 'payments' && isAdmin && (
          <PaymentsTab
            users={users}
            timesheetEntries={timesheetEntries}
            paymentRuns={paymentRuns}
            updatePaymentStatus={updatePaymentStatus}
          />
        )}

        {/* ── CIS TAB ── */}
        {tab === 'cis' && isAdmin && (
          <CISTab
            timesheetEntries={timesheetEntries}
            users={users}
            leads={leads.map(l => ({ id: l.id, address: l.address }))}
          />
        )}

      </div>

      {/* AddDayModal */}
      {activeCell && activeCellUser && (
        <AddDayModal
          date={activeCell.date}
          userId={activeCell.userId}
          userName={activeCellUser.name}
          existingEntry={activeCell.existing}
          dayRate={activeCellUser.dayRate ?? 0}
          cisRate={activeCellUser.cisRate ?? 20}
          leads={leads.map(l => ({ id: l.id, name: l.name, jobRef: l.jobRef }))}
          onSave={(leadId, type, amount) => upsertTimesheetEntry({ userId: activeCell.userId, leadId, date: activeCell.date, type, amount })}
          onDelete={activeCell.existing ? () => deleteTimesheetEntry(activeCell.existing!.id) : undefined}
          onClose={() => setCellTarget(null)}
        />
      )}

      {profileUser && (
        <ProfileModal user={profileUser} onClose={() => setProfileUser(null)} />
      )}

      {showAddCasual && (
        <AddCasualModal
          onSave={(name, rate, cis) => addCasualWorker(name, rate, cis)}
          onClose={() => setShowAddCasual(false)}
        />
      )}
    </div>
  );
}

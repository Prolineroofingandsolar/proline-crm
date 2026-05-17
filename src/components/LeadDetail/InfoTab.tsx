import { useState, useRef } from 'react';
import { Edit3, Save, X, MapPin } from 'lucide-react';
import type { Lead, JobType } from '../../types';
import { useStore } from '../../store/useStore';
import { formatCurrency, formatDate, jobTypeColor } from '../../utils/helpers';

interface NominatimResult {
  display_name: string;
  address?: {
    house_number?: string;
    road?: string;
    town?: string;
    city?: string;
    postcode?: string;
  };
}

const JOB_TYPES: JobType[] = ['Roof Repair', 'Solar Installation', 'New Roof', 'Flat Roof', 'Solar + Battery', 'Guttering', 'Fascias & Soffits', 'Chimney Repair'];

export default function InfoTab({ lead }: { lead: Lead }) {
  const { updateLead } = useStore();
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState({
    name: lead.name, phone: lead.phone, email: lead.email, address: lead.address,
    jobType: lead.jobType, value: String(lead.value), deposit: String(lead.deposit),
    startDate: lead.startDate ?? '', endDate: lead.endDate ?? '',
    source: lead.source, assignedTo: lead.assignedTo,
  });

  const [addressSuggestions, setAddressSuggestions] = useState<NominatimResult[]>([]);
  const [showAddressSuggestions, setShowAddressSuggestions] = useState(false);
  const [addressLoading, setAddressLoading] = useState(false);
  const addressDebounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const set = (k: string, v: string) => setForm(p => ({ ...p, [k]: v }));

  const handleAddressChange = (v: string) => {
    set('address', v);
    clearTimeout(addressDebounceRef.current);
    if (v.trim().length < 3) {
      setAddressSuggestions([]);
      setShowAddressSuggestions(false);
      return;
    }
    addressDebounceRef.current = setTimeout(async () => {
      setAddressLoading(true);
      try {
        const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(v)}&format=json&limit=6&countrycodes=gb&addressdetails=1`;
        const res = await fetch(url, { headers: { 'Accept-Language': 'en', 'User-Agent': 'ProLineCRM/1.0' } });
        const data: NominatimResult[] = await res.json();
        setAddressSuggestions(data);
        setShowAddressSuggestions(data.length > 0);
      } catch {
        setAddressSuggestions([]);
      } finally {
        setAddressLoading(false);
      }
    }, 500);
  };

  const selectAddress = (result: NominatimResult) => {
    const a = result.address;
    let formatted = result.display_name;
    if (a) {
      const parts = [
        a.house_number && a.road ? `${a.house_number} ${a.road}` : a.road,
        a.town ?? a.city,
        a.postcode,
      ].filter(Boolean);
      if (parts.length >= 2) formatted = parts.join(', ');
    }
    set('address', formatted);
    setAddressSuggestions([]);
    setShowAddressSuggestions(false);
  };

  const save = () => {
    const value = parseFloat(form.value) || 0;
    const deposit = parseFloat(form.deposit) || 0;
    updateLead(lead.id, {
      name: form.name, phone: form.phone, email: form.email, address: form.address,
      jobType: form.jobType as JobType, value, deposit, balance: value - deposit,
      startDate: form.startDate || undefined, endDate: form.endDate || undefined,
      source: form.source, assignedTo: form.assignedTo,
    });
    setEditing(false);
  };

  if (editing) {
    return (
      <div className="p-4 space-y-3">
        <div className="grid grid-cols-2 gap-3">
          {[
            { k: 'name', label: 'Customer Name', col: 2 },
            { k: 'phone', label: 'Phone' },
            { k: 'email', label: 'Email' },
          ].map(({ k, label, col }) => (
            <div key={k} className={col === 2 ? 'col-span-2' : ''}>
              <label className="block text-xs font-semibold text-gray-500 mb-1">{label}</label>
              <input value={(form as Record<string, string>)[k]} onChange={e => set(k, e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
            </div>
          ))}
          <div className="col-span-2">
            <label className="block text-xs font-semibold text-gray-500 mb-1">Address</label>
            <div className="relative">
              <input
                value={form.address}
                onChange={e => handleAddressChange(e.target.value)}
                onBlur={() => setTimeout(() => setShowAddressSuggestions(false), 150)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 pr-8 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
                placeholder="Start typing postcode or address…"
                autoComplete="off"
              />
              {addressLoading && (
                <div className="absolute right-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 border-2 border-orange-400 border-t-transparent rounded-full animate-spin" />
              )}
            </div>
            {showAddressSuggestions && (
              <div className="mt-1 border border-gray-200 rounded-xl overflow-hidden bg-white shadow">
                {addressSuggestions.map((result, i) => {
                  const a = result.address;
                  const line1 = a?.house_number && a?.road ? `${a.house_number} ${a.road}` : a?.road ?? '';
                  const line2 = [a?.town ?? a?.city, a?.postcode].filter(Boolean).join(' ');
                  return (
                    <button
                      key={i}
                      type="button"
                      onMouseDown={() => selectAddress(result)}
                      className="w-full flex items-center gap-2.5 px-3 py-2.5 hover:bg-orange-50 text-left transition-colors border-b border-gray-100 last:border-0"
                    >
                      <MapPin size={13} className="text-orange-400 shrink-0" />
                      <div className="min-w-0">
                        {line1 && <p className="text-sm text-gray-800 truncate">{line1}</p>}
                        <p className="text-xs text-gray-400 truncate">{line2 || result.display_name}</p>
                      </div>
                    </button>
                  );
                })}
              </div>
            )}
          </div>
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1">Job Type</label>
            <select value={form.jobType} onChange={e => set('jobType', e.target.value)}
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400">
              {JOB_TYPES.map(t => <option key={t}>{t}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1">Source</label>
            <input value={form.source} onChange={e => set('source', e.target.value)}
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
          </div>
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1">Job Value (£)</label>
            <input type="number" value={form.value} onChange={e => set('value', e.target.value)}
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
          </div>
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1">Deposit (£)</label>
            <input type="number" value={form.deposit} onChange={e => set('deposit', e.target.value)}
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
          </div>
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1">Start Date</label>
            <input type="date" value={form.startDate} onChange={e => set('startDate', e.target.value)}
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
          </div>
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1">End Date</label>
            <input type="date" value={form.endDate} onChange={e => set('endDate', e.target.value)}
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
          </div>
        </div>
        <div className="flex gap-2 pt-1">
          <button onClick={() => setEditing(false)} className="flex items-center gap-1 border border-gray-200 text-gray-500 hover:bg-gray-50 px-4 py-2 rounded-lg text-sm">
            <X size={14} /> Cancel
          </button>
          <button onClick={save} className="flex items-center gap-1 bg-orange-600 text-white hover:bg-orange-700 px-4 py-2 rounded-lg text-sm font-medium">
            <Save size={14} /> Save Changes
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="p-4">
      <div className="flex items-center justify-between mb-4">
        <span className={`text-xs font-semibold px-2.5 py-1 rounded-full ${jobTypeColor(lead.jobType)}`}>{lead.jobType}</span>
        <button onClick={() => setEditing(true)} className="flex items-center gap-1 text-xs text-orange-600 hover:text-orange-800 font-medium">
          <Edit3 size={13} /> Edit
        </button>
      </div>

      <div className="space-y-3">
        <Row label="Reference" value={lead.jobRef} />
        <Row label="Customer" value={lead.name} />
        <Row label="Phone" value={lead.phone} />
        <Row label="Email" value={lead.email} />
        <Row label="Address" value={lead.address} />
        <Row label="Source" value={lead.source} />
        {lead.startDate && <Row label="Start Date" value={formatDate(lead.startDate)} />}
        {lead.endDate && <Row label="End Date" value={formatDate(lead.endDate)} />}
        {lead.completedDate && <Row label="Completed" value={formatDate(lead.completedDate)} />}
        {lead.paidDate && <Row label="Paid" value={formatDate(lead.paidDate)} />}
        <div className="border-t border-gray-100 pt-3 space-y-2">
          <Row label="Job Value" value={formatCurrency(lead.value)} bold />
          <Row label="Deposit" value={`${formatCurrency(lead.deposit)}${lead.depositPaid ? ' ✓ Paid' : ' (unpaid)'}`} />
          <Row label="Balance" value={formatCurrency(lead.balance)} bold />
        </div>
      </div>
    </div>
  );
}

function Row({ label, value, bold }: { label: string; value: string; bold?: boolean }) {
  return (
    <div className="flex items-start gap-4">
      <span className="w-28 shrink-0 text-xs font-semibold text-gray-400 uppercase tracking-wide pt-0.5">{label}</span>
      <span className={`text-sm flex-1 ${bold ? 'font-bold text-gray-800' : 'text-gray-700'}`}>{value || '—'}</span>
    </div>
  );
}

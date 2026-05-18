import { useState, useRef, useEffect } from 'react';
import { X, UserCheck, MapPin, Camera, Loader2 } from 'lucide-react';
import type { JobType, Stage } from '../../types';
import { useStore } from '../../store/useStore';
import { extractLeadFromImage } from '../../lib/gemini';

interface AddressSuggestion {
  display: string;
  value: string;
}

const UK_POSTCODE_RE = /^[a-z]{1,2}\d[a-z\d]?\s*\d[a-z]{2}$/i;

function formatFindAddress(raw: string, postcode: string): string {
  const parts = raw.split(', ').map(p => p.trim()).filter(Boolean);
  if (parts.length >= 2 && /^\d/.test(parts[0])) {
    parts.splice(0, 2, `${parts[0]} ${parts[1]}`);
  }
  parts.push(postcode.toUpperCase());
  return parts.join(', ');
}

const JOB_TYPES: JobType[] = ['Roof Repair', 'Solar Installation', 'New Roof', 'Flat Roof', 'Solar + Battery', 'Guttering', 'Fascias & Soffits', 'Chimney Repair'];
const SOURCES = ['Website', 'Referral', 'Google', 'Facebook', 'Checkatrade', 'MyBuilder', 'Cold Call', 'Other'];

interface Props {
  onClose: () => void;
  defaultStage?: Stage;
}

export default function AddLeadModal({ onClose, defaultStage = 'New Lead' }: Props) {
  const { addLead, contacts } = useStore();
  const [form, setForm] = useState({
    name: '', phone: '', email: '', address: '', lat: '', lng: '',
    jobType: 'Roof Repair' as JobType,
    stage: defaultStage as Stage,
    source: 'Website',
    value: '', deposit: '',
    surveyDate: '', surveyTime: '',
    notes: '',
    myBuilderUrl: '',
  });
  const [suggestions, setSuggestions] = useState<typeof contacts>([]);
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [addressSuggestions, setAddressSuggestions] = useState<AddressSuggestion[]>([]);
  const [showAddressSuggestions, setShowAddressSuggestions] = useState(false);
  const [addressLoading, setAddressLoading] = useState(false);
  const nameRef = useRef<HTMLInputElement>(null);
  const addressDebounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const set = (k: string, v: string) => setForm(p => ({ ...p, [k]: v }));

  const handleNameChange = (v: string) => {
    set('name', v);
    if (v.trim().length < 1) { setSuggestions([]); setShowSuggestions(false); return; }
    const matches = contacts.filter(c => c.name.toLowerCase().includes(v.toLowerCase())).slice(0, 6);
    setSuggestions(matches);
    setShowSuggestions(matches.length > 0);
  };

  const selectContact = (c: typeof contacts[0]) => {
    setForm(p => ({ ...p, name: c.name, phone: c.phone, email: c.email, address: c.address }));
    setSuggestions([]);
    setShowSuggestions(false);
  };

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
        let results: AddressSuggestion[] = [];
        if (UK_POSTCODE_RE.test(v.trim())) {
          const cleanPostcode = v.trim().toUpperCase().replace(/\s+/g, '');
          const res = await fetch(`/api/getaddress/find/${cleanPostcode}`);
          const data: { addresses?: string[]; postcode?: string } = await res.json();
          const postcode = data.postcode ?? v.trim();
          results = (data.addresses ?? []).map(raw => ({
            display: raw,
            value: formatFindAddress(raw, postcode),
          }));
        } else {
          const res = await fetch(`/api/getaddress/autocomplete/${encodeURIComponent(v)}`);
          const data: { suggestions?: { address: string }[] } = await res.json();
          results = (data.suggestions ?? []).map(s => ({ display: s.address, value: s.address }));
        }
        setAddressSuggestions(results);
        setShowAddressSuggestions(results.length > 0);
      } catch {
        setAddressSuggestions([]);
      } finally {
        setAddressLoading(false);
      }
    }, 500);
  };

  const selectAddress = (suggestion: AddressSuggestion) => {
    set('address', suggestion.value);
    setAddressSuggestions([]);
    setShowAddressSuggestions(false);
  };

  // Close suggestions when clicking outside
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (nameRef.current && !nameRef.current.closest('.name-field')?.contains(e.target as Node)) {
        setShowSuggestions(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.name.trim() || !form.phone.trim()) return;
    const value = parseFloat(form.value) || 0;
    const deposit = parseFloat(form.deposit) || 0;
    const lat = parseFloat(form.lat) || undefined;
    const lng = parseFloat(form.lng) || undefined;
    addLead({
      name: form.name.trim(),
      phone: form.phone.trim(),
      email: form.email.trim(),
      address: form.address.trim(),
      ...(lat && lng ? { lat, lng } : {}),
      jobType: form.jobType,
      stage: form.stage,
      source: form.source,
      assignedTo: 'Harman',
      value,
      deposit,
      depositPaid: false,
      balance: value - deposit,
      progress: 0,
      surveyDate: form.surveyDate || undefined,
      surveyTime: form.surveyTime || undefined,
      myBuilderUrl: form.myBuilderUrl.trim() || undefined,
    });
    onClose();
  };

  const [scanning, setScanning] = useState(false);
  const [scanError, setScanError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleScanPhoto = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setScanError(null);
    setScanning(true);
    extractLeadFromImage(file)
      .then(data => {
        setForm(p => ({
          ...p,
          name: data.name ?? p.name,
          phone: data.phone ?? p.phone,
          email: data.email ?? p.email,
          address: data.address ?? p.address,
          jobType: (data.jobType as JobType) ?? p.jobType,
          notes: data.notes ?? p.notes,
        }));
      })
      .catch(err => setScanError(err.message))
      .finally(() => { setScanning(false); e.target.value = ''; });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end md:items-center justify-center bg-black/40 backdrop-blur-sm md:p-4">
      <div className="bg-white md:rounded-2xl rounded-t-2xl shadow-2xl w-full md:max-w-lg max-h-[92dvh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100 shrink-0">
          <h2 className="font-bold text-gray-800 text-lg">Add New Lead</h2>
          <div className="flex items-center gap-2">
            <button type="button" onClick={() => fileInputRef.current?.click()} disabled={scanning}
              className="flex items-center gap-1.5 text-sm font-medium px-3 py-1.5 rounded-lg bg-orange-50 hover:bg-orange-100 text-orange-600 transition-colors disabled:opacity-50">
              {scanning ? <Loader2 size={15} className="animate-spin" /> : <Camera size={15} />}
              {scanning ? 'Scanning…' : 'Scan photo'}
            </button>
            <button type="button" onClick={onClose} className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-500"><X size={18} /></button>
          </div>
        </div>
        <input ref={fileInputRef} type="file" accept="image/*"
          className="hidden" onChange={handleScanPhoto} />

        {/* Form */}
        <form onSubmit={handleSubmit} className="overflow-y-auto p-5 pb-safe space-y-4">
          {scanError && (
            <div className="bg-red-50 border border-red-200 rounded-xl px-4 py-3 text-sm text-red-700">{scanError}</div>
          )}
          <div className="grid grid-cols-2 gap-3">

            {/* Customer name with autocomplete */}
            <div className="col-span-2 name-field relative">
              <label className="block text-xs font-semibold text-gray-600 mb-1">Customer Name *</label>
              <input
                ref={nameRef}
                required
                value={form.name}
                onChange={e => handleNameChange(e.target.value)}
                onFocus={() => suggestions.length > 0 && setShowSuggestions(true)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
                placeholder="Full name"
                autoComplete="off"
              />
              {showSuggestions && (
                <div className="absolute top-full left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg z-10 overflow-hidden">
                  {suggestions.map(c => (
                    <button
                      key={c.id}
                      type="button"
                      onMouseDown={() => selectContact(c)}
                      className="w-full flex items-center gap-3 px-3 py-2.5 hover:bg-orange-50 text-left transition-colors"
                    >
                      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-orange-400 to-purple-500 flex items-center justify-center text-white text-xs font-bold shrink-0">
                        {c.name[0]}
                      </div>
                      <div className="min-w-0">
                        <p className="text-sm font-semibold text-gray-800 truncate">{c.name}</p>
                        <p className="text-xs text-gray-400 truncate">{c.phone}{c.address ? ` · ${c.address}` : ''}</p>
                      </div>
                      <UserCheck size={14} className="text-orange-400 shrink-0 ml-auto" />
                    </button>
                  ))}
                </div>
              )}
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Phone *</label>
              <input required value={form.phone} onChange={e => set('phone', e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" placeholder="07700 900000" />
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Email</label>
              <input type="email" value={form.email} onChange={e => set('email', e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" placeholder="email@example.com" />
            </div>
            <div className="col-span-2 relative">
              <label className="block text-xs font-semibold text-gray-600 mb-1">Address</label>
              <div className="relative">
                <input
                  value={form.address}
                  onChange={e => handleAddressChange(e.target.value)}
                  onBlur={() => setTimeout(() => setShowAddressSuggestions(false), 150)}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 pr-8 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
                  placeholder="Type a postcode for exact addresses…"
                  autoComplete="off"
                />
                {addressLoading && (
                  <div className="absolute right-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 border-2 border-orange-400 border-t-transparent rounded-full animate-spin" />
                )}
              </div>
              {showAddressSuggestions && (
                <div className="absolute top-full left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg z-10 overflow-hidden max-h-44 overflow-y-auto">
                  {addressSuggestions.map((suggestion, i) => {
                    const parts = suggestion.value.split(', ');
                    const line1 = parts[0];
                    const line2 = parts.slice(1).join(', ');
                    return (
                      <button
                        key={i}
                        type="button"
                        onMouseDown={() => selectAddress(suggestion)}
                        className="w-full flex items-center gap-2.5 px-3 py-2 hover:bg-orange-50 text-left transition-colors"
                      >
                        <MapPin size={13} className="text-orange-400 shrink-0" />
                        <div className="min-w-0">
                          <p className="text-sm text-gray-800 truncate">{line1}</p>
                          {line2 && <p className="text-xs text-gray-400 truncate">{line2}</p>}
                        </div>
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Latitude <span className="text-gray-400 font-normal">(optional)</span></label>
              <input type="number" step="any" value={form.lat} onChange={e => set('lat', e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" placeholder="e.g. 51.5074" />
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Longitude <span className="text-gray-400 font-normal">(optional)</span></label>
              <input type="number" step="any" value={form.lng} onChange={e => set('lng', e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" placeholder="e.g. -3.5275" />
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Job Type</label>
              <select value={form.jobType} onChange={e => set('jobType', e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400">
                {JOB_TYPES.map(t => <option key={t}>{t}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Source</label>
              <select value={form.source} onChange={e => set('source', e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400">
                {SOURCES.map(s => <option key={s}>{s}</option>)}
              </select>
            </div>
            {form.source === 'MyBuilder' && (
              <div className="col-span-2">
                <label className="block text-xs font-semibold text-gray-600 mb-1">MyBuilder Job URL</label>
                <input type="url" value={form.myBuilderUrl} onChange={e => set('myBuilderUrl', e.target.value)}
                  className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
                  placeholder="https://www.mybuilder.com/jobs/..." />
              </div>
            )}
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Stage</label>
              <select value={form.stage} onChange={e => set('stage', e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400">
                {['New Lead','Survey Booked','Quote Sent'].map(s => <option key={s}>{s}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Quote Value (£)</label>
              <input type="number" value={form.value} onChange={e => set('value', e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" placeholder="0" />
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Survey Date</label>
              <input type="date" value={form.surveyDate} onChange={e => set('surveyDate', e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Survey Time</label>
              <input type="time" value={form.surveyTime} onChange={e => set('surveyTime', e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
            </div>
          </div>

          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose}
              className="flex-1 border border-gray-200 text-gray-600 hover:bg-gray-50 py-2 rounded-xl text-sm font-medium transition-colors">
              Cancel
            </button>
            <button type="submit"
              className="flex-1 bg-orange-600 hover:bg-orange-700 text-white py-2 rounded-xl text-sm font-bold transition-colors">
              Add Lead
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

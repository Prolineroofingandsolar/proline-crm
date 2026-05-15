import { useState } from 'react';
import { X } from 'lucide-react';
import type { JobType, Stage } from '../../types';
import { useStore } from '../../store/useStore';

const JOB_TYPES: JobType[] = ['Roof Repair', 'Solar Installation', 'New Roof', 'Flat Roof', 'Solar + Battery', 'Guttering', 'Fascias & Soffits', 'Chimney Repair'];
const SOURCES = ['Website', 'Referral', 'Google', 'Facebook', 'Checkatrade', 'MyBuilder', 'Cold Call', 'Other'];

interface Props {
  onClose: () => void;
  defaultStage?: Stage;
}

export default function AddLeadModal({ onClose, defaultStage = 'New Lead' }: Props) {
  const { addLead } = useStore();
  const [form, setForm] = useState({
    name: '', phone: '', email: '', address: '',
    jobType: 'Roof Repair' as JobType,
    stage: defaultStage as Stage,
    source: 'Website',
    value: '', deposit: '',
    surveyDate: '', surveyTime: '',
    notes: '',
  });

  const set = (k: string, v: string) => setForm(p => ({ ...p, [k]: v }));

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.name.trim() || !form.phone.trim()) return;
    const value = parseFloat(form.value) || 0;
    const deposit = parseFloat(form.deposit) || 0;
    addLead({
      name: form.name.trim(),
      phone: form.phone.trim(),
      email: form.email.trim(),
      address: form.address.trim(),
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
    });
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end md:items-center justify-center bg-black/40 backdrop-blur-sm md:p-4">
      <div className="bg-white md:rounded-2xl rounded-t-2xl shadow-2xl w-full md:max-w-lg max-h-[92dvh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h2 className="font-bold text-gray-800 text-lg">Add New Lead</h2>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-500"><X size={18} /></button>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="overflow-y-auto p-5 space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2">
              <label className="block text-xs font-semibold text-gray-600 mb-1">Customer Name *</label>
              <input required value={form.name} onChange={e => set('name', e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" placeholder="Full name" />
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
            <div className="col-span-2">
              <label className="block text-xs font-semibold text-gray-600 mb-1">Address</label>
              <input value={form.address} onChange={e => set('address', e.target.value)}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" placeholder="Street, City, Postcode" />
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

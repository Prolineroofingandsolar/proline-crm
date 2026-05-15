import { useState } from 'react';
import { Save, User, Building2, Bell, Shield, Palette, Trash2 } from 'lucide-react';
import { useStore } from '../store/useStore';

export default function SettingsPage() {
  const { leads } = useStore();
  const [business, setBusiness] = useState({ name: 'Proline Roofing & Solar Ltd', phone: '01234 567890', email: 'info@proline.co.uk', address: 'Birmingham, West Midlands', vat: 'GB123456789' });
  const [saved, setSaved] = useState(false);

  const handleSave = () => { setSaved(true); setTimeout(() => setSaved(false), 2000); };

  return (
    <div className="p-6 overflow-y-auto h-full bg-white space-y-5">
      {/* Business details */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="flex items-center gap-2 px-5 py-4 border-b border-gray-100">
          <Building2 size={18} className="text-orange-500" />
          <h2 className="font-bold text-gray-800">Business Details</h2>
        </div>
        <div className="p-5 grid grid-cols-1 sm:grid-cols-2 gap-4">
          {[
            { k: 'name', label: 'Business Name' },
            { k: 'phone', label: 'Phone Number' },
            { k: 'email', label: 'Email Address' },
            { k: 'address', label: 'Address' },
            { k: 'vat', label: 'VAT Number' },
          ].map(({ k, label }) => (
            <div key={k}>
              <label className="block text-xs font-semibold text-gray-500 mb-1">{label}</label>
              <input value={(business as Record<string, string>)[k]}
                onChange={e => setBusiness(p => ({ ...p, [k]: e.target.value }))}
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
            </div>
          ))}
        </div>
        <div className="px-5 pb-5">
          <button onClick={handleSave}
            className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${saved ? 'bg-green-100 text-green-700' : 'bg-orange-600 text-white hover:bg-orange-700'}`}>
            <Save size={15} /> {saved ? 'Saved!' : 'Save Changes'}
          </button>
        </div>
      </div>

      {/* Team */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="flex items-center gap-2 px-5 py-4 border-b border-gray-100">
          <User size={18} className="text-orange-500" />
          <h2 className="font-bold text-gray-800">Team Members</h2>
        </div>
        <div className="p-5 space-y-3">
          {[
            { name: 'Harman', role: 'Owner', email: 'harman@proline.co.uk' },
          ].map(m => (
            <div key={m.name} className="flex items-center gap-3 p-3 rounded-xl border border-gray-100 hover:border-gray-200">
              <div className="w-10 h-10 rounded-full bg-orange-100 text-orange-700 font-bold flex items-center justify-center shrink-0">{m.name[0]}</div>
              <div className="flex-1">
                <p className="text-sm font-semibold text-gray-800">{m.name}</p>
                <p className="text-xs text-gray-400">{m.email}</p>
              </div>
              <span className="text-xs bg-orange-100 text-orange-700 font-medium px-2 py-0.5 rounded-full">{m.role}</span>
            </div>
          ))}
          <button className="text-sm text-orange-600 hover:text-orange-800 font-medium">+ Invite team member</button>
        </div>
      </div>

      {/* Notifications */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="flex items-center gap-2 px-5 py-4 border-b border-gray-100">
          <Bell size={18} className="text-orange-500" />
          <h2 className="font-bold text-gray-800">Notifications</h2>
        </div>
        <div className="p-5 space-y-3">
          {[
            'New lead added',
            'Survey reminder (24h before)',
            'Job status changed',
            'Payment received',
            'Task overdue',
          ].map(item => (
            <label key={item} className="flex items-center justify-between cursor-pointer">
              <span className="text-sm text-gray-700">{item}</span>
              <input type="checkbox" defaultChecked className="w-4 h-4 accent-orange-600" />
            </label>
          ))}
        </div>
      </div>

      {/* Pipeline stages */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="flex items-center gap-2 px-5 py-4 border-b border-gray-100">
          <Palette size={18} className="text-orange-500" />
          <h2 className="font-bold text-gray-800">Pipeline Stages</h2>
        </div>
        <div className="p-5 space-y-2">
          {['New Lead', 'Survey Booked', 'Quote Sent', 'Won', 'In Progress', 'Completed', 'Paid'].map((stage, i) => (
            <div key={stage} className="flex items-center gap-3 p-2 rounded-lg border border-gray-100">
              <span className="w-5 h-5 rounded-full bg-orange-100 text-orange-700 flex items-center justify-center text-xs font-bold shrink-0">{i + 1}</span>
              <span className="text-sm text-gray-700 flex-1">{stage}</span>
              <span className="text-xs text-gray-300">Default</span>
            </div>
          ))}
        </div>
      </div>

      {/* Data */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="flex items-center gap-2 px-5 py-4 border-b border-gray-100">
          <Shield size={18} className="text-orange-500" />
          <h2 className="font-bold text-gray-800">Data & Privacy</h2>
        </div>
        <div className="p-5 space-y-3">
          <p className="text-sm text-gray-600">Total records: <strong>{leads.length}</strong></p>
          <button className="flex items-center gap-2 text-sm text-red-500 hover:text-red-700 font-medium">
            <Trash2 size={14} /> Export all data (CSV)
          </button>
        </div>
      </div>
    </div>
  );
}

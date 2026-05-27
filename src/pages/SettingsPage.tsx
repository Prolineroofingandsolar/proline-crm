import { useState } from 'react';
import { useEffect } from 'react';
import { Save, User, Building2, Bell, Shield, Palette, Trash2, Plus, Key, LogOut, X } from 'lucide-react';
import { useStore } from '../store/useStore';

type AddUserForm = { name: string; username: string; password: string; confirm: string; role: 'admin' | 'user' };
type ChangePwForm = { id: string; newPw: string; confirm: string };

export default function SettingsPage() {
  const { leads, users, currentUserId, addUser, deleteUser, changePassword, logout, enablePushNotifications, pushEnabled, pushPreferences, setPushPreference } = useStore();

  const [business, setBusiness] = useState({ name: 'Proline Roofing & Solar Ltd', phone: '01234 567890', email: 'info@proline.co.uk', address: 'Birmingham, West Midlands', vat: 'GB123456789' });
  const [saved, setSaved] = useState(false);

  const [showAddUser, setShowAddUser] = useState(false);
  const [addForm, setAddForm] = useState<AddUserForm>({ name: '', username: '', password: '', confirm: '', role: 'user' });
  const [addError, setAddError] = useState('');
  const [addLoading, setAddLoading] = useState(false);

  const [changePw, setChangePw] = useState<ChangePwForm | null>(null);
  const [changePwError, setChangePwError] = useState('');
  const [changePwLoading, setChangePwLoading] = useState(false);

  const handleSave = () => { setSaved(true); setTimeout(() => setSaved(false), 2000); };

  const [notifPermission, setNotifPermission] = useState<string>(() => {
    if (typeof window === 'undefined' || !('Notification' in window)) return 'unsupported';
    return Notification.permission;
  });
  const [notifLoading, setNotifLoading] = useState(false);

  useEffect(() => {
    if ('Notification' in window) setNotifPermission(Notification.permission);
  }, []);

  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches ||
    (window.navigator as unknown as { standalone?: boolean }).standalone === true;

  const handleEnableNotifications = async () => {
    setNotifLoading(true);
    await enablePushNotifications();
    if ('Notification' in window) setNotifPermission(Notification.permission);
    setNotifLoading(false);
  };

  const handleAddUser = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!addForm.name.trim()) return setAddError('Name is required');
    if (addForm.username.trim().length < 3) return setAddError('Username must be at least 3 characters');
    if (addForm.password.length < 6) return setAddError('Password must be at least 6 characters');
    if (addForm.password !== addForm.confirm) return setAddError('Passwords do not match');
    setAddLoading(true);
    const result = await addUser(addForm.name.trim(), addForm.username.trim(), addForm.password, addForm.role);
    setAddLoading(false);
    if (!result.ok) return setAddError(result.error ?? 'Failed');
    setShowAddUser(false);
    setAddForm({ name: '', username: '', password: '', confirm: '', role: 'user' });
    setAddError('');
  };

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!changePw) return;
    if (changePw.newPw.length < 6) return setChangePwError('Password must be at least 6 characters');
    if (changePw.newPw !== changePw.confirm) return setChangePwError('Passwords do not match');
    setChangePwLoading(true);
    await changePassword(changePw.id, changePw.newPw);
    setChangePwLoading(false);
    setChangePw(null);
    setChangePwError('');
  };

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

      {/* Accounts */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <div className="flex items-center gap-2">
            <User size={18} className="text-orange-500" />
            <h2 className="font-bold text-gray-800">Accounts</h2>
          </div>
          <div className="flex items-center gap-2">
            <button onClick={() => { setShowAddUser(true); setAddError(''); }}
              className="flex items-center gap-1.5 text-xs font-semibold bg-orange-600 text-white px-3 py-1.5 rounded-lg hover:bg-orange-700 transition-colors">
              <Plus size={13} /> Add Account
            </button>
            <button onClick={logout}
              className="flex items-center gap-1.5 text-xs font-semibold border border-gray-200 text-gray-600 px-3 py-1.5 rounded-lg hover:bg-gray-50 transition-colors">
              <LogOut size={13} /> Sign Out
            </button>
          </div>
        </div>
        <div className="p-5 space-y-3">
          {users.filter(u => u.role !== 'casual').map(u => (
            <div key={u.id} className={`flex items-center gap-3 p-3 rounded-xl border transition-colors ${u.id === currentUserId ? 'border-orange-200 bg-orange-50' : 'border-gray-100 hover:border-gray-200'}`}>
              <div className="w-10 h-10 rounded-full bg-orange-100 text-orange-700 font-bold flex items-center justify-center shrink-0 text-sm">
                {u.name[0].toUpperCase()}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-gray-800 truncate">
                  {u.name} {u.id === currentUserId && <span className="text-xs text-orange-500 font-medium">(you)</span>}
                </p>
                <p className="text-xs text-gray-400">@{u.username}</p>
              </div>
              <span className={`text-xs font-medium px-2 py-0.5 rounded-full shrink-0 ${u.role === 'admin' ? 'bg-orange-100 text-orange-700' : 'bg-gray-100 text-gray-600'}`}>
                {u.role === 'admin' ? 'Admin' : 'User'}
              </span>
              <div className="flex items-center gap-1 shrink-0">
                <button onClick={() => { setChangePw({ id: u.id, newPw: '', confirm: '' }); setChangePwError(''); }}
                  title="Change password"
                  className="p-1.5 rounded-lg hover:bg-orange-100 text-gray-400 hover:text-orange-600 transition-colors">
                  <Key size={13} />
                </button>
                {u.id !== currentUserId && (
                  <button onClick={() => { if (window.confirm(`Delete ${u.name}?`)) deleteUser(u.id); }}
                    title="Delete account"
                    className="p-1.5 rounded-lg hover:bg-red-50 text-gray-300 hover:text-red-500 transition-colors">
                    <Trash2 size={13} />
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Add User Modal */}
      {showAddUser && (
        <div className="fixed inset-0 z-50 flex items-end md:items-center justify-center bg-black/40 backdrop-blur-sm p-4">
          <div className="bg-white rounded-2xl shadow-2xl w-full max-w-sm">
            <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
              <h3 className="font-bold text-gray-800">Add New Account</h3>
              <button onClick={() => setShowAddUser(false)} className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-400"><X size={16} /></button>
            </div>
            <form onSubmit={handleAddUser} className="p-5 space-y-4">
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Full Name</label>
                <input required value={addForm.name} onChange={e => { setAddForm(p => ({ ...p, name: e.target.value })); setAddError(''); }}
                  placeholder="e.g. John"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
              </div>
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Username</label>
                <input required value={addForm.username} onChange={e => { setAddForm(p => ({ ...p, username: e.target.value })); setAddError(''); }}
                  placeholder="Choose a username" autoCapitalize="none" autoCorrect="off"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
              </div>
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Password</label>
                <input required type="password" value={addForm.password} onChange={e => { setAddForm(p => ({ ...p, password: e.target.value })); setAddError(''); }}
                  placeholder="Min. 6 characters"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
              </div>
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Confirm Password</label>
                <input required type="password" value={addForm.confirm} onChange={e => { setAddForm(p => ({ ...p, confirm: e.target.value })); setAddError(''); }}
                  placeholder="Repeat password"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
              </div>
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Role</label>
                <select value={addForm.role} onChange={e => setAddForm(p => ({ ...p, role: e.target.value as 'admin' | 'user' }))}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400">
                  <option value="admin">Admin — full access</option>
                  <option value="user">User — standard access</option>
                </select>
              </div>
              {addError && <p className="text-sm text-red-600 bg-red-50 rounded-lg px-3 py-2">{addError}</p>}
              <div className="flex gap-3 pt-1">
                <button type="button" onClick={() => setShowAddUser(false)}
                  className="flex-1 border border-gray-200 text-gray-600 hover:bg-gray-50 py-2.5 rounded-xl text-sm font-medium">Cancel</button>
                <button type="submit" disabled={addLoading}
                  className="flex-1 bg-orange-600 hover:bg-orange-700 disabled:opacity-60 text-white py-2.5 rounded-xl text-sm font-bold transition-colors">
                  {addLoading ? 'Creating…' : 'Create Account'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Change Password Modal */}
      {changePw && (
        <div className="fixed inset-0 z-50 flex items-end md:items-center justify-center bg-black/40 backdrop-blur-sm p-4">
          <div className="bg-white rounded-2xl shadow-2xl w-full max-w-sm">
            <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
              <h3 className="font-bold text-gray-800">Change Password</h3>
              <button onClick={() => setChangePw(null)} className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-400"><X size={16} /></button>
            </div>
            <form onSubmit={handleChangePassword} className="p-5 space-y-4">
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">New Password</label>
                <input required type="password" value={changePw.newPw}
                  onChange={e => { setChangePw(p => p ? { ...p, newPw: e.target.value } : p); setChangePwError(''); }}
                  placeholder="Min. 6 characters"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
              </div>
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Confirm New Password</label>
                <input required type="password" value={changePw.confirm}
                  onChange={e => { setChangePw(p => p ? { ...p, confirm: e.target.value } : p); setChangePwError(''); }}
                  placeholder="Repeat new password"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
              </div>
              {changePwError && <p className="text-sm text-red-600 bg-red-50 rounded-lg px-3 py-2">{changePwError}</p>}
              <div className="flex gap-3 pt-1">
                <button type="button" onClick={() => setChangePw(null)}
                  className="flex-1 border border-gray-200 text-gray-600 hover:bg-gray-50 py-2.5 rounded-xl text-sm font-medium">Cancel</button>
                <button type="submit" disabled={changePwLoading}
                  className="flex-1 bg-orange-600 hover:bg-orange-700 disabled:opacity-60 text-white py-2.5 rounded-xl text-sm font-bold transition-colors">
                  {changePwLoading ? 'Saving…' : 'Save Password'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Notifications */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="flex items-center gap-2 px-5 py-4 border-b border-gray-100">
          <Bell size={18} className="text-orange-500" />
          <h2 className="font-bold text-gray-800">Push Notifications</h2>
        </div>
        <div className="p-5 space-y-4">
          {isIOS && !isStandalone ? (
            <div className="bg-orange-50 border border-orange-100 rounded-xl p-4 space-y-1">
              <p className="text-sm font-semibold text-orange-800">Install the app first</p>
              <p className="text-sm text-orange-700">
                Open this page in Safari, tap the <strong>Share</strong> button, then <strong>Add to Home Screen</strong>. Reopen from your home screen and come back here to enable notifications.
              </p>
            </div>
          ) : (
            <>
              <p className="text-sm text-gray-500">
                Get notified on this device for key events. Each team member enables notifications on their own phone.
              </p>
              <div className="space-y-1">
                {([
                  { key: 'newLead',        label: 'New lead added' },
                  { key: 'surveyBooked',   label: 'Survey booked' },
                  { key: 'jobWon',         label: 'Job won' },
                  { key: 'jobStarted',     label: 'Job started' },
                  { key: 'jobCompleted',   label: 'Job completed' },
                  { key: 'paymentReceived', label: 'Payment received' },
                ] as const).map(({ key, label }) => (
                  <div key={key} className="flex items-center justify-between py-2 px-3 rounded-xl hover:bg-gray-50">
                    <span className={`text-sm ${pushEnabled ? 'text-gray-700' : 'text-gray-400'}`}>{label}</span>
                    <button
                      role="switch"
                      aria-checked={pushPreferences[key]}
                      disabled={!pushEnabled}
                      onClick={() => setPushPreference(key, !pushPreferences[key])}
                      className={`relative inline-flex h-6 w-11 shrink-0 rounded-full transition-colors focus:outline-none ${
                        !pushEnabled ? 'cursor-not-allowed opacity-40' :
                        pushPreferences[key] ? 'bg-orange-500' : 'bg-gray-200'
                      }`}
                    >
                      <span className={`inline-block h-5 w-5 rounded-full bg-white shadow transform transition-transform mt-0.5 ${pushPreferences[key] ? 'translate-x-5' : 'translate-x-0.5'}`} />
                    </button>
                  </div>
                ))}
              </div>
              <button
                onClick={handleEnableNotifications}
                disabled={
                  notifPermission === 'denied' ||
                  notifPermission === 'unsupported' ||
                  notifLoading ||
                  (notifPermission === 'granted' && pushEnabled)
                }
                className={`flex items-center justify-center gap-2 w-full px-4 py-2.5 rounded-xl text-sm font-semibold transition-colors ${
                  notifPermission === 'granted' && pushEnabled
                    ? 'bg-green-100 text-green-700'
                    : notifPermission === 'denied'
                    ? 'bg-red-50 text-red-500 cursor-not-allowed'
                    : notifPermission === 'unsupported'
                    ? 'bg-gray-100 text-gray-400 cursor-not-allowed'
                    : 'bg-orange-600 text-white hover:bg-orange-700'
                }`}
              >
                <Bell size={15} />
                {notifPermission === 'granted' && pushEnabled
                  ? 'Notifications enabled on this device'
                  : notifPermission === 'denied'
                  ? 'Blocked — allow in device Settings'
                  : notifPermission === 'unsupported'
                  ? 'Not supported on this browser'
                  : notifLoading
                  ? 'Enabling…'
                  : 'Enable push notifications'}
              </button>
              {notifPermission === 'denied' && (
                <p className="text-xs text-red-400">
                  Go to Settings → {isIOS ? 'Safari → ProLine' : 'your browser'} → Notifications → Allow.
                </p>
              )}
            </>
          )}
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

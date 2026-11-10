import { useState } from 'react';
import { useEffect } from 'react';
import { Trash2, Bell, Shield, Palette, Key, LogOut, X } from 'lucide-react';
import StaffManager from '../components/Staff/StaffManager';
import CompanyDetails from '../components/Staff/CompanyDetails';
import { useStore } from '../store/useStore';
import { getDeviceNotificationPermission, isMacApp, sendDeviceNotification } from '../utils/push';
import VirtualOfficeSettings from '../components/VirtualOffice/VirtualOfficeSettings';

type ChangePwForm = { id: string; newPw: string; confirm: string };

export default function SettingsPage() {
  const { leads, users, currentUserId, changePassword, logout, enablePushNotifications, disablePushNotifications, pushEnabled, pushPreferences, setPushPreference } = useStore();

  const [changePw, setChangePw] = useState<ChangePwForm | null>(null);
  const [changePwError, setChangePwError] = useState('');
  const [changePwLoading, setChangePwLoading] = useState(false);

  const [notifPermission, setNotifPermission] = useState<string>('default');
  const [notifLoading, setNotifLoading] = useState(false);

  useEffect(() => {
    void getDeviceNotificationPermission().then(setNotifPermission);
  }, []);

  const isMac = isMacApp();
  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches ||
    (window.navigator as unknown as { standalone?: boolean }).standalone === true;

  const handleEnableNotifications = async () => {
    setNotifLoading(true);
    await enablePushNotifications();
    setNotifPermission(await getDeviceNotificationPermission());
    setNotifLoading(false);
  };

  const handleTestNotification = () => {
    void sendDeviceNotification('ProLine CRM', 'Native Mac notifications are working.');
  };

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!changePw) return;
    if (changePw.newPw.length < 8) return setChangePwError('Password must be at least 8 characters');
    if (changePw.newPw !== changePw.confirm) return setChangePwError('Passwords do not match');
    setChangePwLoading(true);
    try { await changePassword(changePw.id, changePw.newPw); }
    catch (error) { setChangePwError(error instanceof Error ? error.message : 'Password change failed'); setChangePwLoading(false); return; }
    setChangePwLoading(false);
    setChangePw(null);
    setChangePwError('');
  };

  return (
    <div className="p-6 overflow-y-auto h-full bg-white space-y-5">
      <CompanyDetails />

      <StaffManager />
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-gray-200 p-5">
        <div><h2 className="font-bold text-gray-800">Your account</h2><p className="text-sm text-gray-500">{users.find(u => u.id === currentUserId)?.name}</p></div>
        <div className="flex gap-3"><button onClick={() => { if (currentUserId) setChangePw({ id: currentUserId, newPw: '', confirm: '' }); }} className="flex items-center gap-2 rounded-lg border px-3 py-2 text-sm"><Key size={15} />Change password</button><button onClick={logout} className="flex items-center gap-2 rounded-lg border px-3 py-2 text-sm"><LogOut size={15} />Sign out</button></div>
      </div>

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
                  placeholder="Min. 8 characters"
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
          <h2 className="font-bold text-gray-800">{isMac ? 'Mac Notifications' : 'Push Notifications'}</h2>
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
                {isMac
                  ? 'Receive native Notification Centre alerts for CRM activity, even while this window is in the background.'
                  : 'Get notified on this device for key events. Each team member enables notifications on their own phone.'}
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
              <div className="flex items-center justify-between py-2 px-3 rounded-xl bg-gray-50">
                <div className="flex items-center gap-2">
                  <Bell size={15} className={pushEnabled ? 'text-orange-500' : 'text-gray-400'} />
                  <span className="text-sm font-medium text-gray-700">
                    {notifPermission === 'denied' ? 'Blocked in device Settings'
                      : notifPermission === 'unsupported' ? 'Not supported on this browser'
                      : pushEnabled ? 'Notifications on'
                      : notifLoading ? 'Enabling…'
                      : 'Notifications off'}
                  </span>
                </div>
                <button
                  role="switch"
                  aria-checked={pushEnabled}
                  disabled={notifPermission === 'denied' || notifPermission === 'unsupported' || notifLoading}
                  onClick={pushEnabled ? disablePushNotifications : handleEnableNotifications}
                  className={`relative inline-flex h-6 w-11 shrink-0 rounded-full transition-colors focus:outline-none ${
                    notifPermission === 'denied' || notifPermission === 'unsupported' ? 'cursor-not-allowed opacity-40 bg-gray-200'
                    : pushEnabled ? 'bg-orange-500'
                    : 'bg-gray-200'
                  }`}
                >
                  <span className={`inline-block h-5 w-5 rounded-full bg-white shadow transform transition-transform mt-0.5 ${pushEnabled ? 'translate-x-5' : 'translate-x-0.5'}`} />
                </button>
              </div>
              {notifPermission === 'denied' && (
                <p className="text-xs text-red-400">
                  Go to System Settings → Notifications → ProLine CRM → Allow Notifications.
                </p>
              )}
              {isMac && pushEnabled && (
                <button
                  type="button"
                  onClick={handleTestNotification}
                  className="text-sm font-semibold text-orange-600 hover:text-orange-700 px-3 py-2 rounded-lg hover:bg-orange-50"
                >
                  Send test notification
                </button>
              )}
            </>
          )}
        </div>
      </div>

      <VirtualOfficeSettings />

      {/* Pipeline stages */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="flex items-center gap-2 px-5 py-4 border-b border-gray-100">
          <Palette size={18} className="text-orange-500" />
          <h2 className="font-bold text-gray-800">Pipeline Stages</h2>
        </div>
        <div className="p-5 space-y-2">
          {['New Lead', 'Survey Booked', 'Quote Sent', 'Won', 'In Progress', 'Completed', 'Waiting for Payment', 'Paid'].map((stage, i) => (
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

import { useState } from 'react';
import { useStore } from '../store/useStore';

function ProLineLogo() {
  return (
    <svg viewBox="0 0 220 165" fill="none" xmlns="http://www.w3.org/2000/svg" className="w-full h-full">
      <polygon points="92,42 2,18 2,36" fill="#ea580c"/>
      <polygon points="92,42 2,41 2,59" fill="#ea580c"/>
      <polygon points="92,42 2,64 2,82" fill="#ea580c"/>
      <polygon points="92,42 2,87 2,105" fill="#ea580c"/>
      <path d="M92,42 L122,16 L148,68 L188,10 L188,2 L203,2 L203,10 L218,145"
            stroke="white" strokeWidth="9" strokeLinecap="round" strokeLinejoin="round"/>
      <path d="M92,42 L124,25 L150,71 L190,19 L218,131"
            stroke="white" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round"/>
      <path d="M92,42 L126,34 L152,73 L192,28 L218,117"
            stroke="white" strokeWidth="7" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  );
}

interface Props {
  mode: 'login' | 'setup';
}

export default function LoginPage({ mode }: Props) {
  const { login, addUser } = useStore();
  const [form, setForm] = useState({ name: '', username: '', password: '', confirm: '' });
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const set = (k: string, v: string) => { setForm(p => ({ ...p, [k]: v })); setError(''); };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    const ok = await login(form.username.trim(), form.password);
    if (!ok) setError('Incorrect username or password');
    setLoading(false);
  };

  const handleSetup = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.name.trim()) return setError('Name is required');
    if (form.username.trim().length < 3) return setError('Username must be at least 3 characters');
    if (form.password.length < 6) return setError('Password must be at least 6 characters');
    if (form.password !== form.confirm) return setError('Passwords do not match');
    setLoading(true);
    const result = await addUser(form.name.trim(), form.username.trim(), form.password, 'admin');
    if (!result.ok) { setError(result.error ?? 'Failed to create account'); setLoading(false); return; }
    await login(form.username.trim(), form.password);
    setLoading(false);
  };

  const isSetup = mode === 'setup';

  return (
    <div className="min-h-screen bg-gray-950 flex flex-col items-center justify-center p-6">
      {/* Card */}
      <div className="w-full max-w-sm bg-white rounded-3xl shadow-2xl overflow-hidden">
        {/* Header */}
        <div className="bg-gray-900 px-8 pt-8 pb-6 flex flex-col items-center gap-3">
          <div className="w-16 h-12">
            <ProLineLogo />
          </div>
          <div className="text-center">
            <p className="text-white font-bold text-xl tracking-tight">ProLine CRM</p>
            <p className="text-gray-400 text-xs mt-0.5">Roofing & Solar</p>
          </div>
        </div>

        {/* Form */}
        <div className="px-8 py-7">
          <h2 className="text-lg font-bold text-gray-800 mb-1">
            {isSetup ? 'Create your account' : 'Welcome back'}
          </h2>
          <p className="text-sm text-gray-400 mb-5">
            {isSetup ? 'Set up the first admin account to get started.' : 'Sign in to continue to your CRM.'}
          </p>

          <form onSubmit={isSetup ? handleSetup : handleLogin} className="space-y-4">
            {isSetup && (
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Your Name</label>
                <input
                  required
                  value={form.name}
                  onChange={e => set('name', e.target.value)}
                  placeholder="e.g. Harman"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
                />
              </div>
            )}

            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Username</label>
              <input
                required
                value={form.username}
                onChange={e => set('username', e.target.value)}
                placeholder={isSetup ? 'Choose a username' : 'Your username'}
                autoCapitalize="none"
                autoCorrect="off"
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
              />
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Password</label>
              <input
                required
                type="password"
                value={form.password}
                onChange={e => set('password', e.target.value)}
                placeholder={isSetup ? 'Min. 6 characters' : 'Your password'}
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
              />
            </div>

            {isSetup && (
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Confirm Password</label>
                <input
                  required
                  type="password"
                  value={form.confirm}
                  onChange={e => set('confirm', e.target.value)}
                  placeholder="Repeat password"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
                />
              </div>
            )}

            {error && (
              <p className="text-sm text-red-600 bg-red-50 rounded-lg px-3 py-2">{error}</p>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full bg-orange-600 hover:bg-orange-700 disabled:opacity-60 text-white font-bold py-3 rounded-xl text-sm transition-colors"
            >
              {loading ? (isSetup ? 'Creating…' : 'Signing in…') : (isSetup ? 'Create Account' : 'Sign In')}
            </button>
          </form>
        </div>
      </div>

      <p className="text-gray-600 text-xs mt-6">ProLine Roofing & Solar Ltd</p>
    </div>
  );
}

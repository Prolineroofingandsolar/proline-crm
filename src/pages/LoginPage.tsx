import { useState } from 'react';
import { supabase } from '../lib/supabase';
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
  mode: 'login' | 'recovery';
}

export default function LoginPage({ mode }: Props) {
  const { login } = useStore();
  const [form, setForm] = useState({ name: '', username: '', password: '', confirm: '' });
  const [recovery, setRecovery] = useState(mode === 'recovery');
  const [recoverySent, setRecoverySent] = useState(false);
  const [code, setCode] = useState('');
  const [joining, setJoining] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const set = (k: string, v: string) => { setForm(p => ({ ...p, [k]: v })); setError(''); };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    try {
      if (joining) {
        const { data, error } = await supabase.functions.invoke('worker-invite', { body: { action: 'accept', token: code.trim(), name: form.name.trim(), password: form.password } });
        if (error || data?.error) throw new Error(data?.error ?? error?.message ?? 'Invitation could not be accepted');
        if (!await login(data.email, form.password)) throw new Error('Account created. Please sign in with your invited email.');
      } else if (recovery) {
        if (mode === 'recovery') {
          const { error } = await supabase.auth.updateUser({ password: form.password });
          if (error) throw error;
          window.location.replace(window.location.origin);
        } else if (!recoverySent) {
          const { error } = await supabase.auth.resetPasswordForEmail(form.username.trim(), { redirectTo: window.location.origin });
          if (error) throw error;
          setRecoverySent(true);
        } else {
          const { error: verifyError } = await supabase.auth.verifyOtp({ email: form.username.trim(), token: code.trim(), type: 'recovery' });
          if (verifyError) throw verifyError;
          const { error: updateError } = await supabase.auth.updateUser({ password: form.password });
          if (updateError) throw updateError;
          window.location.replace(window.location.origin);
        }
      } else if (!await login(form.username.trim(), form.password)) setError('Incorrect email or password, or access has been removed.');
    } catch (error) { setError(error instanceof Error ? error.message : 'Sign-in failed. Please try again.'); }
    setLoading(false);
  };

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
            {joining ? 'Accept invitation' : recovery ? 'Reset password' : 'Welcome back'}
          </h2>
          <p className="text-sm text-gray-400 mb-5">
            Sign in using your employee email, or accept your administrator’s invitation.
          </p>

          {(joining || (recovery && recoverySent)) && <label className="block text-sm mb-4">{joining ? 'Invitation code from your administrator' : 'Recovery code from your email'}<input required value={code} onChange={e => setCode(e.target.value)} className="w-full border rounded-xl p-3 mt-1" /></label>}
          {recoverySent && <p className="text-sm mb-3">Check your email. Follow the reset link, or enter its recovery code and a new password here.</p>}
          <form onSubmit={handleLogin} className="space-y-4">
            {joining && (
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
              <label className="block text-xs font-semibold text-gray-600 mb-1">Email</label>
              <input
                required={mode !== 'recovery' && !joining}
                type="email"
                autoComplete="username"
                value={form.username}
                onChange={e => set('username', e.target.value)}
                placeholder="you@company.co.uk"
                autoCapitalize="none"
                autoCorrect="off"
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
              />
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Password</label>
              <input
                required={!recovery || recoverySent || mode === 'recovery'}
                type="password"
                minLength={(recovery && recoverySent) || mode === 'recovery' || joining ? 8 : undefined}
                value={form.password}
                onChange={e => set('password', e.target.value)}
                placeholder="Your password"
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
              />
            </div>

            {error && (
              <p className="text-sm text-red-600 bg-red-50 rounded-lg px-3 py-2">{error}</p>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full bg-orange-600 hover:bg-orange-700 disabled:opacity-60 text-white font-bold py-3 rounded-xl text-sm transition-colors"
            >
              {loading ? 'Please wait…' : joining ? 'Join team' : recovery ? (recoverySent || mode === 'recovery' ? 'Save new password' : 'Send recovery email') : 'Sign In'}
            </button>
          </form>
          <div className="flex flex-wrap gap-3 mt-4 text-sm text-orange-700">
            <button type="button" onClick={() => { setRecovery(!recovery); setJoining(false); setError(''); }}>{recovery ? 'Back to sign in' : 'Forgot password?'}</button>
            <button type="button" onClick={() => { setJoining(!joining); setRecovery(false); setError(''); }}>{joining ? 'Back to sign in' : 'Have an invitation?'}</button>
          </div>
        </div>
      </div>

      <p className="text-gray-600 text-xs mt-6">ProLine Roofing & Solar Ltd</p>
    </div>
  );
}

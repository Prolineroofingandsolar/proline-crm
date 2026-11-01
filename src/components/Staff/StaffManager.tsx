import { useCallback, useEffect, useRef, useState } from 'react';
import { Users, Search, Plus, Send, ShieldCheck, ChevronRight, X, Copy, Check, RefreshCw, AlertCircle } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import type { AppUser } from '../../types';
import { useStore } from '../../store/useStore';
type Role = 'admin' | 'worker' | 'labourer';
type Person = {
    id: string;
    name: string;
    email: string | null;
    role: string;
    active: boolean;
    day_rate: number | null;
    cis_rate: number | null;
};
type PayDetails = { utr_number: string | null; bank_name: string | null; bank_account_number: string | null; bank_sort_code: string | null };
type Invitation = {
    id: string;
    email: string;
    role: string;
    expires_at: string;
};
const roles: Record<Role, {
    label: string;
    description: string;
}> = {
    worker: { label: 'Worker', description: 'Works on assigned jobs, tasks and their own timesheets.' },
    labourer: { label: 'Labourer', description: 'A team member who can be recorded on jobs and payroll.' },
    admin: { label: 'Administrator', description: 'Manages the company, staff, customers and finances.' },
};
const roleLabel = (role: string) => roles[role as Role]?.label ?? (role === 'user' ? 'Worker' : 'Payroll worker');
const input = 'w-full rounded-xl border border-gray-200 bg-white px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500';
async function staffRequest(body: Record<string, unknown>) {
    const { data, error } = await supabase.functions.invoke('worker-invite', { body });
    if (error) {
        const response = 'context' in error && error.context instanceof Response ? await error.context.json().catch(() => null) : null;
        throw new Error(response?.error ?? error.message);
    }
    if (data?.error)
        throw new Error(data.error);
    return data;
}
function updateRoster(people: Person[]) {
    useStore.setState(state => ({ users: people.filter(person => person.active).map(person => ({
            ...state.users.find(user => user.id === person.id), id: person.id, name: person.name,
            username: person.email ?? '', role: person.role as AppUser['role'], passwordHash: '',
            createdAt: state.users.find(user => user.id === person.id)?.createdAt ?? '',
            dayRate: person.day_rate ?? undefined, cisRate: (person.cis_rate ?? 20) as 20 | 30,
        })) }));
}
function Dialog({ title, close, children, busy = false }: {
    title: string;
    close: () => void;
    children: React.ReactNode;
    busy?: boolean;
}) {
    const ref = useRef<HTMLDialogElement>(null);
    useEffect(() => { ref.current?.showModal(); }, []);
    return <dialog ref={ref} aria-label={title} onCancel={e => { e.preventDefault(); if (!busy)
        close(); }} className="m-auto max-h-[90dvh] w-[calc(100%_-_2rem)] max-w-lg overflow-y-auto rounded-2xl bg-white p-0 text-gray-900 shadow-2xl backdrop:bg-gray-950/50">
    <div className="flex items-center justify-between border-b px-6 py-4"><h3 className="text-lg font-bold">{title}</h3><button aria-label="Close" disabled={busy} onClick={close} className="rounded-lg p-2 hover:bg-gray-100 disabled:opacity-40"><X size={18}/></button></div>
    {children}
  </dialog>;
}
export default function StaffManager() {
    const currentUserId = useStore(s => s.currentUserId);
    const [staff, setStaff] = useState<Person[]>([]);
    const [invitations, setInvitations] = useState<Invitation[]>([]);
    const [now, setNow] = useState(() => Date.now());
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [notice, setNotice] = useState('');
    const [query, setQuery] = useState('');
    const [filter, setFilter] = useState('active');
    const [adding, setAdding] = useState(false);
    const [selected, setSelected] = useState<Person | null>(null);
    const [busy, setBusy] = useState(false);
    const [payDetails, setPayDetails] = useState<PayDetails | null>(null);
    const [originalPay, setOriginalPay] = useState<PayDetails | null>(null);
    const [confirm, setConfirm] = useState(false);
    const [mode, setMode] = useState<'invite' | 'account' | 'payroll'>('invite');
    const [form, setForm] = useState({ name: '', email: '', password: '', role: 'worker' as Role, rate: '', cis: '20' });
    const [invite, setInvite] = useState<{
        code: string;
        email: string;
        expires_at: string;
    } | null>(null);
    const [copied, setCopied] = useState(false);
    const load = useCallback(async () => {
        setLoading(true);
        setError('');
        try {
            const data = await staffRequest({ action: 'list_staff' });
            setStaff(data.staff);
            updateRoster(data.staff);
            setInvitations(data.invitations);
            setNow(Date.now());
        }
        catch (e) {
            setError(e instanceof Error ? e.message : 'Staff could not be loaded.');
        }
        finally {
            setLoading(false);
        }
    }, []);
    useEffect(() => {
        let active = true;
        void staffRequest({ action: 'list_staff' }).then(data => {
            if (active) {
                setStaff(data.staff);
                updateRoster(data.staff);
                setInvitations(data.invitations);
                setNow(Date.now());
            }
        }).catch(e => { if (active)
            setError(e instanceof Error ? e.message : 'Staff could not be loaded.'); })
            .finally(() => { if (active)
            setLoading(false); });
        return () => { active = false; };
    }, []);
    const perform = async (body: Record<string, unknown>, success: string) => {
        setBusy(true);
        setError('');
        try {
            await staffRequest(body);
            setSelected(null);
            setConfirm(false);
            setNotice(success);
            await load();
        }
        catch (e) {
            setError(e instanceof Error ? e.message : 'The change could not be saved.');
        }
        finally {
            setBusy(false);
        }
    };
    const openAdd = () => { setForm({ name: '', email: '', password: '', role: 'worker', rate: '', cis: '20' }); setMode('invite'); setNotice(''); setInvite(null); setError(''); setCopied(false); setAdding(true); };
    const openPerson = (person: Person) => { setPayDetails(null); setOriginalPay(null); setSelected(person); setConfirm(false); setError(''); setForm({ name: person.name, email: person.email ?? '', password: '', role: (person.role === 'admin' || person.role === 'labourer') ? person.role : 'worker', rate: person.day_rate == null ? '' : String(person.day_rate), cis: String(person.cis_rate ?? 20) }); };
    const loadPayDetails = async (id: string) => {
        setBusy(true); setError('');
        try { const data = await staffRequest({ action: 'get_pay_details', user_id: id }); setPayDetails(data.details); setOriginalPay(data.details); }
        catch (e) { setError(e instanceof Error ? e.message : 'Pay details could not be loaded.'); }
        finally { setBusy(false); }
    };
    const submit = async (event: React.FormEvent) => {
        event.preventDefault();
        setBusy(true);
        setError('');
        try {
            if (mode === 'invite') {
                const data = await staffRequest({ action: 'create', email: form.email.trim(), role: form.role });
                setInvite(data);
                await load();
            }
            else {
                await staffRequest({ action: 'create_user', name: form.name.trim(), email: mode === 'payroll' ? '' : form.email.trim(), password: mode === 'payroll' ? '' : form.password, role: form.role, day_rate: form.rate === '' ? null : Number(form.rate), cis_rate: Number(form.cis) });
                setAdding(false);
                setNotice('Staff member added.');
                await load();
            }
        }
        catch (e) {
            setError(e instanceof Error ? e.message : 'Staff member could not be added.');
        }
        finally {
            setBusy(false);
        }
    };
    const active = staff.filter(p => p.active);
    const matches = staff.filter(p => (filter === 'all' || (filter === 'removed' ? !p.active : p.active)) && `${p.name} ${p.email ?? ''} ${roleLabel(p.role)}`.toLowerCase().includes(query.toLowerCase()));
    const pending = invitations.filter(i => new Date(i.expires_at).getTime() > now);
    const errorBox = error && <p role="alert" className="flex items-start gap-2 rounded-xl bg-red-50 p-3 text-sm text-red-700"><AlertCircle size={18} className="shrink-0"/>{error}</p>;
    const rolePicker = <label className="block text-sm font-medium">Role<select className={`${input} mt-1`} value={form.role} onChange={e => setForm({ ...form, role: e.target.value as Role })}>{Object.entries(roles).filter(([key]) => !adding || mode !== 'payroll' || key !== 'admin').map(([value, role]) => <option key={value} value={value}>{role.label}</option>)}</select><span className="mt-2 block text-xs font-normal text-gray-500">{roles[form.role].description}</span></label>;
    const payFields = <div className="grid grid-cols-2 gap-3"><label className="text-sm font-medium">Day rate (£)<input type="number" min="0" max="10000" step="0.01" className={`${input} mt-1`} value={form.rate} placeholder="Not set" onChange={e => setForm({ ...form, rate: e.target.value })}/></label><label className="text-sm font-medium">CIS deduction<select className={`${input} mt-1`} value={form.cis} onChange={e => setForm({ ...form, cis: e.target.value })}><option value="20">20%</option><option value="30">30%</option></select></label></div>;
    return <section className="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm">
    <div className="flex flex-wrap items-center justify-between gap-4 border-b border-gray-100 p-5 sm:p-6"><div><h2 className="flex items-center gap-2 text-xl font-bold"><Users className="text-orange-600" size={22}/> Staff & access</h2><p className="mt-1 text-sm text-gray-500">Manage your team, invitations and access to ProLine.</p></div><button onClick={openAdd} className="flex items-center gap-2 rounded-xl bg-orange-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-orange-700"><Plus size={17}/>Add staff</button></div>
    <div className="space-y-5 p-5 sm:p-6">
      <div className="grid grid-cols-3 gap-3">{[[String(active.length), 'Active staff'], [String(active.filter(p => p.role === 'admin').length), 'Administrators'], [String(pending.length), 'Pending invites']].map(([count, label]) => <div key={label} className="rounded-xl bg-gray-50 p-3 sm:p-4"><p className="text-2xl font-bold">{loading || (!selected && !adding && error) ? '—' : count}</p><p className="text-xs text-gray-500">{label}</p></div>)}</div>
      {notice && <p role="status" className="rounded-xl bg-green-50 p-3 text-sm text-green-800">{notice}</p>}
      {!adding && !selected && errorBox}
      <div className="flex flex-wrap gap-3"><label className="relative min-w-0 flex-1"><span className="sr-only">Search staff</span><Search size={17} className="absolute left-3 top-3 text-gray-400"/><input className={`${input} pl-9`} value={query} placeholder="Search name, email or role" onChange={e => setQuery(e.target.value)}/></label><select aria-label="Filter staff" className="rounded-xl border border-gray-200 px-3 text-sm" value={filter} onChange={e => setFilter(e.target.value)}><option value="active">Active staff</option><option value="removed">Removed access</option><option value="all">All staff</option></select><button aria-label="Refresh staff" disabled={loading || busy} onClick={() => void load()} className="rounded-xl border p-3 disabled:opacity-40"><RefreshCw size={17} className={loading ? 'animate-spin' : ''}/></button></div>
      {loading ? <p className="py-8 text-center text-sm text-gray-500">Loading staff…</p> : (!selected && !adding && error) ? null : <div className="divide-y divide-gray-100">{matches.map(person => <button key={person.id} onClick={() => openPerson(person)} className="flex w-full items-center gap-3 rounded-xl px-2 py-4 text-left hover:bg-gray-50"><span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-orange-50 font-bold text-orange-700">{person.name.trim().split(/\s+/).map(w => w[0]).slice(0, 2).join('') || '?'}</span><span className="min-w-0 flex-1"><span className="block truncate font-semibold">{person.name}{person.id === currentUserId && <span className="ml-2 text-xs font-normal text-gray-400">You</span>}</span><span className="block truncate text-xs text-gray-500">{person.email || 'Payroll only · no app login'}</span><span className="mt-1 block text-xs text-gray-500">{roleLabel(person.role)}{person.day_rate != null && ` · £${person.day_rate.toFixed(2)}/day`}</span></span><span className={`rounded-full px-2.5 py-1 text-xs font-medium ${person.active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{person.active ? 'Active' : 'Removed'}</span><ChevronRight size={16} className="shrink-0 text-gray-400"/></button>)}{!matches.length && <p className="py-8 text-center text-sm text-gray-500">{query ? 'No staff match your search.' : filter === 'removed' ? 'No removed staff. Work history stays available when access is removed.' : 'No staff in this view. Add a team member to get started.'}</p>}</div>}
      {invitations.length > 0 && <div className="border-t pt-5"><h3 className="mb-3 flex items-center gap-2 text-sm font-bold"><Send size={16}/> Invitations</h3><p className="mb-3 text-xs text-gray-500">Codes are shared manually. Create a new invitation if the original code has been lost.</p>{invitations.filter(i => i.email.toLowerCase().includes(query.toLowerCase())).map(i => <div key={i.id} className="flex flex-wrap items-center gap-3 border-b border-gray-100 py-3"><div className="min-w-0 flex-1"><p className="truncate text-sm font-medium">{i.email}</p><p className="text-xs text-gray-500">{roleLabel(i.role)} · {new Date(i.expires_at).getTime() > now ? `Expires ${new Date(i.expires_at).toLocaleDateString('en-GB')}` : 'Expired'}</p></div><button disabled={busy} onClick={() => { if (window.confirm(`Cancel the invitation for ${i.email}?`))
        void perform({ action: 'cancel_invite', invitation_id: i.id }, 'Invitation cancelled.'); }} className="rounded-lg px-3 py-2 text-xs font-semibold text-red-700 hover:bg-red-50 disabled:opacity-40">Cancel invite</button></div>)}</div>}
    </div>
    {adding && <Dialog title={invite ? 'Invitation ready' : 'Add staff member'} close={() => setAdding(false)} busy={busy}><div className="p-6">{invite ? <div className="space-y-4"><div className="flex items-center gap-2 text-green-700"><ShieldCheck size={22}/><p className="font-semibold">Ready to share with {invite.email}</p></div><p className="text-sm text-gray-500">Send this code privately. They can select “Have an invitation?” online or “Join your team with an invite” in the app and choose their own password.</p><p className="select-all break-all rounded-xl border bg-gray-50 p-4 font-mono text-sm">{invite.code}</p><button className="flex items-center gap-2 rounded-xl bg-orange-600 px-4 py-3 text-sm font-semibold text-white" onClick={async () => { try {
        await navigator.clipboard.writeText(invite.code);
        setCopied(true);
    }
    catch {
        setError('Select and copy the code above. Clipboard access is unavailable.');
    } }}>{copied ? <Check size={16}/> : <Copy size={16}/>}{copied ? 'Copied' : 'Copy invitation code'}</button><p className="text-xs text-gray-500">Single use · expires {new Date(invite.expires_at).toLocaleDateString('en-GB')}</p>{errorBox}</div> : <form onSubmit={submit} className="space-y-4"><div className="grid grid-cols-3 gap-1 rounded-xl bg-gray-100 p-1">{([['invite', 'Invite'], ['account', 'Set up login'], ['payroll', 'Payroll only']] as const).map(([value, label]) => <button type="button" key={value} onClick={() => { setMode(value); setError(''); if (value === 'payroll')
        setForm({ ...form, role: 'labourer' }); }} className={`rounded-lg px-2 py-2 text-xs font-semibold ${mode === value ? 'bg-white shadow-sm' : 'text-gray-500'}`}>{label}</button>)}</div><p className="text-sm text-gray-500">{mode === 'invite' ? 'Invite someone to choose their own password. No email is sent automatically.' : mode === 'account' ? 'Create their login now. Share the temporary password privately and ask them to change it.' : 'Add someone to timesheets and payroll without giving them app access.'}</p>{mode !== 'invite' && <label className="block text-sm font-medium">Full name<input required className={`${input} mt-1`} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })}/></label>}{mode !== 'payroll' && <label className="block text-sm font-medium">Email address<input required type="email" autoComplete="off" className={`${input} mt-1`} value={form.email} onChange={e => setForm({ ...form, email: e.target.value })}/></label>}{mode === 'account' && <label className="block text-sm font-medium">Temporary password<input required type="password" minLength={8} autoComplete="new-password" className={`${input} mt-1`} value={form.password} onChange={e => setForm({ ...form, password: e.target.value })}/><span className="mt-1 block text-xs text-gray-500">At least 8 characters.</span></label>}{rolePicker}{mode !== 'invite' && payFields}{errorBox}<button disabled={busy} className="w-full rounded-xl bg-orange-600 p-3 font-semibold text-white disabled:opacity-50">{busy ? 'Saving…' : mode === 'invite' ? 'Create invitation' : 'Add staff member'}</button></form>}</div></Dialog>}
    {selected && <Dialog title={selected.name} close={() => setSelected(null)} busy={busy}><div className="space-y-5 p-6"><div className="rounded-xl bg-gray-50 p-4 text-sm"><p className="font-medium">{selected.email || 'Payroll only · no app login'}</p><p className="mt-1 text-gray-500">{selected.active ? 'Active staff member' : 'Access removed · work history retained'}</p></div>{selected.id === currentUserId ? <p className="text-sm text-gray-500">This is your account. Another administrator must change your role or pay settings. You cannot remove your own access.</p> : <form onSubmit={e => { e.preventDefault(); void perform({ action: 'update_staff_details', user_id: selected.id, name: form.name.trim(), role: form.role, day_rate: form.rate === '' ? null : Number(form.rate), cis_rate: Number(form.cis) }, 'Staff details saved.'); }} className="space-y-4"><label className="block text-sm font-medium">Full name<input required maxLength={120} className={`${input} mt-1`} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })}/></label>{rolePicker}{payFields}{errorBox}<button disabled={busy} className="w-full rounded-xl bg-orange-600 p-3 text-sm font-semibold text-white disabled:opacity-50">{busy ? 'Saving…' : 'Save staff details'}</button></form>}{selected.id !== currentUserId && selected.email && <form onSubmit={e => { e.preventDefault(); void perform({ action: 'update_staff_email', user_id: selected.id, email: form.email.trim() }, 'Sign-in email updated. The employee must use the new email to sign in.'); }} className="space-y-3 border-t pt-4"><label className="block text-sm font-medium">Sign-in email<input required type="email" maxLength={254} className={`${input} mt-1`} value={form.email} onChange={e => setForm({ ...form, email: e.target.value })}/></label><p className="text-xs text-gray-500">The employee will sign in with this email and their existing password. Share the new address with them securely.</p>{errorBox}<button disabled={busy || form.email.trim().toLowerCase() === selected.email.toLowerCase()} className="rounded-xl border px-4 py-2.5 text-sm font-semibold disabled:opacity-50">Update sign-in email</button></form>}{selected.id !== currentUserId && <div className="space-y-3 border-t pt-4"><p className="text-sm font-semibold">Bank and tax details</p>{!payDetails ? <button type="button" disabled={busy} onClick={() => void loadPayDetails(selected.id)} className="rounded-xl border px-4 py-2 text-sm disabled:opacity-50">Load bank and tax details</button> : <form className="space-y-3" onSubmit={e => { e.preventDefault(); void perform({ action: 'update_pay_details', user_id: selected.id, ...payDetails, expected: originalPay }, 'Bank and tax details saved.'); }}>{([['utr_number', 'UTR (10 digits)'], ['bank_name', 'Bank name'], ['bank_account_number', 'Account number (8 digits)'], ['bank_sort_code', 'Sort code (6 digits)']] as const).map(([key, label]) => <label key={key} className="block text-sm font-medium">{label}<input autoComplete="off" className={`${input} mt-1`} value={payDetails[key] ?? ''} onChange={e => setPayDetails({ ...payDetails, [key]: e.target.value })}/></label>)}<button disabled={busy} className="rounded-xl border px-4 py-2 text-sm font-semibold disabled:opacity-50">Save bank and tax details</button></form>}{errorBox}</div>}<div className="border-t pt-4"><p className="mb-3 text-xs text-gray-500">Passwords are managed by each employee using “Forgot password?” on the sign-in screen.</p>{selected.id !== currentUserId && (confirm ? <div className="space-y-3 rounded-xl bg-red-50 p-4"><p className="text-sm text-red-800">Remove {selected.name}’s access? Their jobs, timesheets and payments will be kept.</p><div className="flex gap-3"><button disabled={busy} onClick={() => void perform({ action: 'deactivate', user_id: selected.id }, 'Staff access removed. Work history has been kept.')} className="rounded-lg bg-red-600 px-3 py-2 text-sm font-semibold text-white">Confirm removal</button><button disabled={busy} onClick={() => setConfirm(false)} className="text-sm">Keep access</button></div></div> : <button disabled={busy} onClick={() => selected.active ? setConfirm(true) : void perform({ action: 'restore', user_id: selected.id }, 'Staff access restored.')} className={`rounded-xl border px-4 py-2.5 text-sm font-semibold disabled:opacity-50 ${selected.active ? 'border-red-200 text-red-700' : 'border-green-200 text-green-700'}`}>{selected.active ? 'Remove access' : 'Restore staff access'}</button>)}</div>{confirm && errorBox}</div></Dialog>}
  </section>;
}

import { useEffect, useState } from 'react';
import { Building2 } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { useStore } from '../../store/useStore';

type Details = { name: string; phone: string; email: string; address: string; vat: string };
export default function CompanyDetails() {
  const organisationId = useStore(s => s.users.find(u => u.id === s.currentUserId)?.organisationId);
  const [details, setDetails] = useState<Details>({ name: '', phone: '', email: '', address: '', vat: '' });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(false);
  useEffect(() => {
    if (!organisationId) return;
    let active = true;
    void supabase.from('organisations').select('name,phone,email,address,vat').eq('id', organisationId).single().then(({ data, error }) => {
      if (!active) return;
      if (error) setError('Company details could not be loaded. Refresh and try again.');
      else setDetails(data as Details);
      setLoading(false);
    });
    return () => { active = false; };
  }, [organisationId]);
  const save = async (event: React.FormEvent) => {
    event.preventDefault(); setSaving(true); setError(''); setSaved(false);
    try {
      if (!organisationId) throw new Error('Your company profile could not be loaded.');
      const { error } = await supabase.from('organisations').update({ ...details, name: details.name.trim() }).eq('id', organisationId).select('id').single();
      if (error) throw error;
      setSaved(true);
    } catch { setError('Company details could not be saved. Your changes are still shown.'); }
    finally { setSaving(false); }
  };
  return <section className="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm">
    <div className="flex items-center gap-2 border-b px-5 py-4"><Building2 size={18} className="text-orange-600" /><h2 className="font-bold">Company details</h2></div>
    <form onSubmit={save} className="space-y-4 p-5">
      <p className="text-sm text-gray-500">Shared company details for ProLine across your apps.</p>
      <fieldset disabled={loading || saving} className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {(Object.entries({ name: 'Business name', phone: 'Phone', email: 'Email', address: 'Address', vat: 'VAT number' }) as [keyof Details, string][]).map(([key, label]) => <label key={key} className="text-xs font-semibold text-gray-600">{label}<input required={key === 'name'} type={key === 'email' ? 'email' : 'text'} value={details[key]} onChange={e => { setDetails({ ...details, [key]: e.target.value }); setSaved(false); }} className="mt-1 w-full rounded-xl border px-3 py-2.5 text-sm font-normal disabled:bg-gray-50" /></label>)}
      </fieldset>
      {error && <p role="alert" className="text-sm text-red-700">{error}</p>}
      {saved && <p role="status" className="text-sm text-green-700">Company details saved.</p>}
      <button disabled={loading || saving || !organisationId} className="rounded-xl bg-orange-600 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-50">{loading ? 'Loading…' : saving ? 'Saving…' : 'Save company details'}</button>
    </form>
  </section>;
}

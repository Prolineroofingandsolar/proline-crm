import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

function parseLocator(locator: string): { bucket: string; path: string } | null {
  if (!locator.startsWith('storage://')) return null;
  const withoutScheme = locator.slice('storage://'.length);
  const slash = withoutScheme.indexOf('/');
  if (slash < 1 || slash === withoutScheme.length - 1) return null;
  return { bucket: withoutScheme.slice(0, slash), path: withoutScheme.slice(slash + 1) };
}

export function useStorageAsset(locator?: string): string | undefined {
  const [url, setUrl] = useState<string | undefined>(() => locator && !locator.startsWith('storage://') ? locator : undefined);
  useEffect(() => {
    let active = true;
    setUrl(locator && !locator.startsWith('storage://') ? locator : undefined);
    const parsed = locator ? parseLocator(locator) : null;
    if (!parsed) return () => { active = false; };
    void supabase.storage.from(parsed.bucket).createSignedUrl(parsed.path, 3600).then(({ data, error }) => {
      if (active && !error) setUrl(data.signedUrl);
    });
    return () => { active = false; };
  }, [locator]);
  return url;
}

export function StorageImage({ locator, ...props }: { locator: string } & Omit<React.ImgHTMLAttributes<HTMLImageElement>, 'src'>) {
  const url = useStorageAsset(locator);
  if (!url) return <div aria-label={props.alt} className={props.className} />;
  return <img {...props} src={url} />;
}

export async function removeStoredObject(locator?: string): Promise<void> {
  const parsed = locator ? parseLocator(locator) : null;
  if (parsed) await supabase.storage.from(parsed.bucket).remove([parsed.path]);
}

export async function uploadStoredObject(file: File, leadId: string): Promise<string> {
  if (file.size > 25 * 1024 * 1024) throw new Error('Files must be 25 MB or smaller.');
  const { data: authData } = await supabase.auth.getUser();
  let organisationId = 'legacy';
  if (authData.user) {
    const { data: profile, error: profileError } = await supabase.from('profiles').select('organisation_id').eq('id', authData.user.id).single();
    if (profileError || !profile?.organisation_id) throw new Error('Your organisation profile is incomplete.');
    organisationId = profile.organisation_id as string;
  }
  const safeName = file.name.replace(/[^A-Za-z0-9._-]/g, '-');
  const path = `${organisationId}/leads/${leadId}/${crypto.randomUUID()}-${safeName || 'attachment'}`;
  const { error } = await supabase.storage.from('crm-attachments').upload(path, file, { contentType: file.type || 'application/octet-stream', upsert: false });
  if (error) throw error;
  return `storage://crm-attachments/${path}`;
}

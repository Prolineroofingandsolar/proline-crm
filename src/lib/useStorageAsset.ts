import { useEffect, useState } from 'react';
import { supabase } from './supabase';
import { parseLocator } from './storage';

export function useStorageAsset(locator?: string): string | undefined {
  const [signed, setSigned] = useState<{ locator: string; url: string } | null>(null);
  useEffect(() => {
    let active = true;
    const parsed = locator ? parseLocator(locator) : null;
    if (!parsed || !locator) return;
    let timer: ReturnType<typeof setTimeout>;
    const renew = async () => {
      const { data, error } = await supabase.storage.from(parsed.bucket).createSignedUrl(parsed.path, 3600);
      if (active && !error && data) {
        setSigned({ locator, url: data.signedUrl });
        timer = setTimeout(() => { void renew(); }, 50 * 60 * 1000);
      }
    };
    void renew();
    return () => { active = false; clearTimeout(timer); };
  }, [locator]);
  if (!locator?.startsWith('storage://')) return locator;
  return signed?.locator === locator ? signed.url : undefined;
}

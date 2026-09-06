-- ProLine CRM Auth/RLS phase 1: additive foundation.
-- Safe to deploy before user invitations; this phase does not enable RLS.
begin;

create extension if not exists pgcrypto;

create table if not exists public.organisations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

insert into public.organisations (id, name)
values ('00000000-0000-0000-0000-000000000001', 'ProLine Roofing & Solar Ltd')
on conflict (id) do nothing;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  organisation_id uuid not null references public.organisations(id),
  legacy_user_id text unique,
  email text,
  username text,
  name text not null,
  role text not null default 'user' check (role in ('admin', 'user', 'casual')),
  active boolean not null default true,
  day_rate numeric,
  cis_rate integer default 20 check (cis_rate in (20, 30)),
  utr_number text,
  bank_name text,
  bank_account_number text,
  bank_sort_code text,
  created_at timestamptz not null default now()
);

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'leads', 'contacts', 'general_tasks', 'timesheet_entries',
    'payment_runs', 'worker_payments', 'push_subscriptions'
  ] loop
    if to_regclass('public.' || table_name) is not null then
      execute format('alter table public.%I add column if not exists organisation_id uuid references public.organisations(id)', table_name);
      execute format('update public.%I set organisation_id = $1 where organisation_id is null', table_name)
        using '00000000-0000-0000-0000-000000000001'::uuid;
    end if;
  end loop;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'crm-attachments', 'crm-attachments', false, 26214400,
  array['image/jpeg','image/png','image/heic','image/heif','image/webp','application/pdf','text/plain','text/csv','application/zip','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

commit;

-- Before phase 2:
-- 1. Invite each non-casual app_users account through Supabase Auth.
-- 2. Insert one profiles row per invited user, setting legacy_user_id.
-- 3. Verify every active employee can sign in on web, macOS, and iOS.

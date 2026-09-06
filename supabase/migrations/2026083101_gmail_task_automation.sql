begin;
create table if not exists public.gmail_connections (
  id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, gmail_address text not null,
  refresh_token_cipher text not null, enabled boolean not null default true, last_scanned_at timestamptz,
  created_at timestamptz not null default now(), unique (organisation_id, gmail_address)
);
create table if not exists public.gmail_oauth_states (
  state text primary key, organisation_id uuid not null references public.organisations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, expires_at timestamptz not null default now() + interval '15 minutes'
);
create table if not exists public.gmail_processed_messages (
  organisation_id uuid not null references public.organisations(id) on delete cascade, message_id text not null,
  outcome text not null, task_id text, processed_at timestamptz not null default now(), primary key (organisation_id, message_id)
);
alter table public.gmail_connections enable row level security;
alter table public.gmail_oauth_states enable row level security;
alter table public.gmail_processed_messages enable row level security;
revoke all on public.gmail_connections, public.gmail_oauth_states, public.gmail_processed_messages from anon, authenticated;
commit;

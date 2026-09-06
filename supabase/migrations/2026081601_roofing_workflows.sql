-- Structured roofing surveys and customer quotes.
-- Apply after 2026080902_enforce_rls.sql.

create table if not exists public.roof_surveys (
  id text primary key,
  organisation_id uuid not null default public.current_organisation_id(),
  lead_id text not null references public.leads(id) on delete cascade,
  status text not null default 'planned' check (status in ('planned','in_progress','completed')),
  surveyor_id uuid references auth.users(id),
  scheduled_at text,
  completed_at text,
  roof_type text not null default '',
  covering text not null default '',
  storeys integer not null default 1 check (storeys between 1 and 20),
  pitch_degrees numeric,
  access_notes text not null default '',
  scaffold_required boolean not null default false,
  asbestos_suspected boolean not null default false,
  hazards jsonb not null default '[]'::jsonb,
  measurements jsonb not null default '[]'::jsonb,
  findings text not null default '',
  recommendations text not null default '',
  created_at text not null default '',
  updated_at text not null default ''
);

create table if not exists public.quotes (
  id text primary key,
  organisation_id uuid not null default public.current_organisation_id(),
  lead_id text not null references public.leads(id) on delete cascade,
  quote_number text not null,
  status text not null default 'draft' check (status in ('draft','sent','accepted','declined','expired')),
  line_items jsonb not null default '[]'::jsonb,
  vat_rate numeric not null default 20,
  discount numeric not null default 0,
  valid_until text,
  terms text not null default '',
  customer_message text not null default '',
  sent_at text,
  accepted_at text,
  created_at text not null default '',
  updated_at text not null default '',
  unique (organisation_id, quote_number)
);

create index if not exists roof_surveys_lead_idx on public.roof_surveys(lead_id);
create index if not exists quotes_lead_idx on public.quotes(lead_id);
alter table public.roof_surveys enable row level security;
alter table public.quotes enable row level security;

drop policy if exists roof_surveys_org_access on public.roof_surveys;
create policy roof_surveys_org_access on public.roof_surveys for all to authenticated
using (organisation_id = public.current_organisation_id())
with check (organisation_id = public.current_organisation_id());

drop policy if exists quotes_org_access on public.quotes;
create policy quotes_org_access on public.quotes for all to authenticated
using (organisation_id = public.current_organisation_id())
with check (organisation_id = public.current_organisation_id());

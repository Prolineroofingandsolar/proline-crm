-- ProLine CRM — Supabase schema
-- Paste this into the Supabase SQL Editor and click Run

create table if not exists leads (
  id text primary key,
  job_ref text not null default '',
  name text not null default '',
  phone text not null default '',
  email text not null default '',
  address text not null default '',
  job_type text not null default 'Roof Repair',
  stage text not null default 'New Lead',
  value numeric not null default 0,
  deposit numeric not null default 0,
  deposit_paid boolean not null default false,
  balance numeric not null default 0,
  source text not null default '',
  assigned_to text not null default '',
  survey_date text,
  survey_time text,
  start_date text,
  end_date text,
  completed_date text,
  paid_date text,
  won_date text,
  progress integer not null default 0,
  lat double precision,
  lng double precision,
  tasks jsonb not null default '[]',
  photos jsonb not null default '[]',
  notes jsonb not null default '[]',
  files jsonb not null default '[]',
  materials jsonb not null default '[]',
  created_at text not null default '',
  updated_at text not null default ''
);

create table if not exists app_users (
  id text primary key,
  name text not null default '',
  username text unique not null,
  password_hash text not null default '',
  role text not null default 'user',
  created_at text not null default ''
);

create table if not exists contacts (
  id text primary key,
  name text not null default '',
  phone text not null default '',
  email text not null default '',
  address text not null default '',
  created_at text not null default ''
);

create table if not exists general_tasks (
  id text primary key,
  title text not null default '',
  completed boolean not null default false,
  completed_date text,
  due_date text,
  priority text not null default 'medium',
  category text not null default '',
  notes text,
  created_at text not null default ''
);

-- No RLS — app has its own login gate
alter table leads disable row level security;
alter table app_users disable row level security;
alter table contacts disable row level security;
alter table general_tasks disable row level security;

-- Timesheet migration
-- Run this if upgrading an existing database (safe to run multiple times)
alter table app_users add column if not exists day_rate numeric;
alter table app_users add column if not exists cis_rate integer default 20;
alter table app_users add column if not exists utr_number text;
alter table app_users add column if not exists bank_name text;
alter table app_users add column if not exists bank_account_number text;
alter table app_users add column if not exists bank_sort_code text;

create table if not exists push_subscriptions (
  id text primary key,
  user_id text not null default '',
  endpoint text unique not null,
  subscription jsonb not null,
  created_at text not null default ''
);

alter table push_subscriptions disable row level security;

create table if not exists timesheet_entries (
  id text primary key,
  user_id text not null default '',
  lead_id text not null default '',
  date text not null default '',
  type text not null default 'full',
  amount numeric not null default 0,
  created_at text not null default ''
);

alter table timesheet_entries disable row level security;

create table if not exists payment_runs (
  id text primary key,
  user_id text not null,
  week_start text not null,
  status text not null default 'due',
  paid_date text,
  notes text,
  created_at text not null default '',
  unique(user_id, week_start)
);

alter table payment_runs disable row level security;

-- Task assignment migration
alter table general_tasks add column if not exists assigned_to jsonb not null default '[]';

-- RPC used by the Scriptable lock screen widget to get incomplete job tasks
create or replace function get_incomplete_job_tasks()
returns table(lead_name text, lead_ref text, task_id text, task_title text)
language sql
as $$
  select
    l.name       as lead_name,
    l.job_ref    as lead_ref,
    t->>'id'     as task_id,
    t->>'title'  as task_title
  from leads l,
       jsonb_array_elements(l.tasks) as t
  where l.stage in ('Won', 'In Progress', 'Completed')
    and (t->>'completed')::boolean = false;
$$;

-- Trigger: send push notification whenever a lead is inserted from any source
-- (covers both the CRM app and external websites posting directly to Supabase)
CREATE OR REPLACE FUNCTION notify_new_lead()
RETURNS trigger AS $$
BEGIN
  PERFORM net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL') || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'SUPABASE_ANON_KEY')
    ),
    body := jsonb_build_object(
      'title', 'New Lead Added',
      'body', NEW.name || ' — ' || COALESCE(NEW.job_type, 'Job')
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_lead_inserted
AFTER INSERT ON leads
FOR EACH ROW EXECUTE FUNCTION notify_new_lead();

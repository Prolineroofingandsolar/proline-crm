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

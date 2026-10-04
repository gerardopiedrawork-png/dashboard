-- Follow-up migration for later features (from README "Team mode -> 1. Supabase").
-- Run after schema.sql. Safe to re-run.

-- Profile extras: photo, built-in signature, ID, address
alter table public.profiles add column if not exists avatar_url    text;
alter table public.profiles add column if not exists signature_url text;
alter table public.profiles add column if not exists id_number     text;
alter table public.profiles add column if not exists address       text;

-- Contracts: placed fields + captured values (DocuSign-style)
alter table public.contracts add column if not exists fields       jsonb default '[]'::jsonb;
alter table public.contracts add column if not exists field_values jsonb default '{}'::jsonb;

-- SOPs: assign to one employee (and let that employee read theirs)
alter table public.sops add column if not exists assigned_to uuid references public.profiles(id) on delete set null;
drop policy if exists sops_read on public.sops;
create policy sops_read on public.sops for select
  using (public.is_admin() or assigned_to = auth.uid());

-- Departments (admin-managed; shown as clock-in options)
create table if not exists public.departments (
  id   uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);
alter table public.departments enable row level security;
drop policy if exists dept_read  on public.departments;
create policy dept_read  on public.departments for select using (auth.uid() is not null);
drop policy if exists dept_admin on public.departments;
create policy dept_admin on public.departments for all using (public.is_admin()) with check (public.is_admin());

-- Weekly timesheets (employee submits; admin reviews)
create table if not exists public.timesheets (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  week_start  date not null,
  hours       numeric default 0,
  note        text,
  status      text not null default 'submitted',
  submitted_at timestamptz,
  reviewed_at  timestamptz,
  created_at  timestamptz not null default now(),
  unique (user_id, week_start)
);
alter table public.timesheets enable row level security;
drop policy if exists ts_select on public.timesheets;
create policy ts_select on public.timesheets for select
  using (user_id = auth.uid() or public.is_admin());
drop policy if exists ts_write on public.timesheets;
create policy ts_write on public.timesheets for all
  using (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());

-- Server-side config store (holds the Gmail refresh token; service-role only)
create table if not exists public.app_config (
  key   text primary key,
  value text
);
alter table public.app_config enable row level security;  -- no policies = only service_role can touch it

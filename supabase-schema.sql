-- ============================================================
-- Redington Client Ledger — Supabase schema
-- Run this once in: Supabase project → SQL Editor → New query → Run
-- ============================================================

create extension if not exists "uuid-ossp";

-- ---------- PROFILES ----------
-- One row per login account. Links a Supabase Auth user to a role
-- (admin / member) and, for members, to the exact "Sales rep" name
-- used in the quotations table.
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade primary key,
  name text not null,
  email text,
  role text not null check (role in ('admin','member')),
  rep_name text,
  created_at timestamptz default now()
);

alter table public.profiles enable row level security;

-- A user can always read their own profile (needed right after login).
create policy "users can read own profile"
  on public.profiles for select
  using (auth.uid() = id);

-- Admins can read every profile (needed for the "Manage team" list).
create policy "admins can read all profiles"
  on public.profiles for select
  using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- No insert/update/delete policies here on purpose — profiles are only ever
-- created/removed by the /api/create-user and /api/delete-user serverless
-- functions, which use the service_role key and bypass RLS safely server-side.


-- ---------- QUOTATIONS ----------
create table if not exists public.quotations (
  id uuid primary key default uuid_generate_v4(),
  rep text not null,
  company text not null,
  product text,
  value numeric default 0,
  pam text,
  quote_date date,
  status text not null default 'Pending' check (status in ('Pending','Confirmed','PO Received','Cancelled')),
  note text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.quotations enable row level security;

-- SELECT: admins see every row; members see only rows where rep = their linked rep_name.
create policy "admins can select all quotations"
  on public.quotations for select
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

create policy "members can select own quotations"
  on public.quotations for select
  using (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'member' and p.rep_name = quotations.rep
  ));

-- INSERT: admins can insert any row; members can only insert rows attributed to themselves.
create policy "admins can insert quotations"
  on public.quotations for insert
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

create policy "members can insert own quotations"
  on public.quotations for insert
  with check (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'member' and p.rep_name = quotations.rep
  ));

-- UPDATE: same shape as insert.
create policy "admins can update quotations"
  on public.quotations for update
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

create policy "members can update own quotations"
  on public.quotations for update
  using (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'member' and p.rep_name = quotations.rep
  ))
  with check (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'member' and p.rep_name = quotations.rep
  ));

-- DELETE: same shape again.
create policy "admins can delete quotations"
  on public.quotations for delete
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

create policy "members can delete own quotations"
  on public.quotations for delete
  using (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'member' and p.rep_name = quotations.rep
  ));

-- Keep updated_at fresh on every edit.
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_quotations_updated_at on public.quotations;
create trigger trg_quotations_updated_at
  before update on public.quotations
  for each row execute function public.set_updated_at();

-- Enable realtime so the dashboard updates live across devices/tabs.
alter publication supabase_realtime add table public.quotations;

-- ---------- COMPANY-WIDE TOTAL (visible to everyone, without exposing rows) ----------
-- Members can only SELECT their own rows directly (see policies above), but
-- the dashboard is also allowed to show the one company-wide total value to
-- everyone. This function runs with the owner's privileges (security definer),
-- so it can sum every row, while still only ever returning a single number —
-- it never exposes any individual row's data.
create or replace function public.total_pipeline_value()
returns numeric
language sql
security definer
set search_path = public
as $$
  select coalesce(sum(value), 0) from public.quotations;
$$;

grant execute on function public.total_pipeline_value() to authenticated;

-- ============================================================
-- After running this file, create the first admin manually:
-- 1) Authentication → Users → Add user → enter an email + password,
--    tick "Auto Confirm User".
-- 2) Copy the new user's UUID.
-- 3) Run this, replacing the values:
--
-- insert into public.profiles (id, name, email, role, rep_name)
-- values ('PASTE-USER-UUID-HERE', 'Admin', 'admin@redington.com', 'admin', null);
-- ============================================================

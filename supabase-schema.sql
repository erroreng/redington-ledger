-- ============================================================
-- Redington Client Ledger — Supabase schema (v2, recursion-safe)
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

-- ---------- HELPER FUNCTIONS ----------
-- These run with the function owner's privileges (security definer), which
-- lets them check a user's role/rep_name WITHOUT that check itself being
-- subject to profiles' own RLS policies. Without this, a policy on
-- `profiles` that queries `profiles` to check "is this user an admin?"
-- recurses into itself and every query on the table fails with
-- "infinite recursion detected in policy" — these functions are what
-- avoid that.
create or replace function public.is_admin(uid uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(select 1 from public.profiles where id = uid and role = 'admin');
$$;

create or replace function public.my_rep_name(uid uuid)
returns text
language sql
security definer
set search_path = public
as $$
  select rep_name from public.profiles where id = uid and role = 'member';
$$;

grant execute on function public.is_admin(uuid) to authenticated;
grant execute on function public.my_rep_name(uuid) to authenticated;

-- A user can always read their own profile (needed right after login).
create policy "users can read own profile"
  on public.profiles for select
  using (auth.uid() = id);

-- Admins can read every profile (needed for the "Manage team" list).
create policy "admins can read all profiles"
  on public.profiles for select
  using (public.is_admin(auth.uid()));

-- No insert/update/delete policies here on purpose — profiles are only ever
-- created/removed by the /api/create-user and /api/delete-user serverless
-- functions, which use the service_role key and bypass RLS safely server-side.


-- ---------- QUOTATIONS ----------
create table if not exists public.quotations (
  id uuid primary key default uuid_generate_v4(),
  rep text not null,
  company text not null,
  client_name text,
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
  using (public.is_admin(auth.uid()));

create policy "members can select own quotations"
  on public.quotations for select
  using (public.my_rep_name(auth.uid()) = rep);

-- INSERT: admins can insert any row; members can only insert rows attributed to themselves.
create policy "admins can insert quotations"
  on public.quotations for insert
  with check (public.is_admin(auth.uid()));

create policy "members can insert own quotations"
  on public.quotations for insert
  with check (public.my_rep_name(auth.uid()) = rep);

-- UPDATE: same shape as insert.
create policy "admins can update quotations"
  on public.quotations for update
  using (public.is_admin(auth.uid()));

create policy "members can update own quotations"
  on public.quotations for update
  using (public.my_rep_name(auth.uid()) = rep)
  with check (public.my_rep_name(auth.uid()) = rep);

-- DELETE: same shape again.
create policy "admins can delete quotations"
  on public.quotations for delete
  using (public.is_admin(auth.uid()));

create policy "members can delete own quotations"
  on public.quotations for delete
  using (public.my_rep_name(auth.uid()) = rep);

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
-- 2) Run this (safe to re-run; it looks up the id by email itself,
--    so there's no UUID to copy/paste and get wrong):
--
-- insert into public.profiles (id, name, email, role, rep_name)
-- select id, 'Admin', email, 'admin', null
-- from auth.users
-- where email = 'PASTE-THE-ADMIN-EMAIL-HERE'
-- on conflict (id) do update set role = 'admin', name = 'Admin', rep_name = null;
-- ============================================================

-- ============================================================
-- MIGRATING AN EXISTING PROJECT that already has a `quotations` table
-- from before the `client_name` column existed — run this once:
--
-- alter table public.quotations add column if not exists client_name text;
-- ============================================================

-- ============================================================
-- MIGRATING AN EXISTING PROJECT that was set up with the original
-- (recursive) version of this file: if re-running this whole file gives
-- "policy already exists" errors, run this cleanup block first, then
-- run the rest of the file again:
--
-- drop policy if exists "admins can read all profiles" on public.profiles;
-- drop policy if exists "admins can select all quotations" on public.quotations;
-- drop policy if exists "members can select own quotations" on public.quotations;
-- drop policy if exists "admins can insert quotations" on public.quotations;
-- drop policy if exists "members can insert own quotations" on public.quotations;
-- drop policy if exists "admins can update quotations" on public.quotations;
-- drop policy if exists "members can update own quotations" on public.quotations;
-- drop policy if exists "admins can delete quotations" on public.quotations;
-- drop policy if exists "members can delete own quotations" on public.quotations;
-- ============================================================

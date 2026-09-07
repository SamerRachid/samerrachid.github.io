-- Agencies directory: an agency profile per member (one row per user), approved by the admin,
-- listed publicly with the areas it serves and its live listings.
create table if not exists public.agencies (
  id bigserial primary key,
  user_id uuid not null unique references public.users(id) on delete cascade,
  name text not null,
  description text,
  phone text, whatsapp text, email text, website text, address text,
  gov_names text[] not null default '{}',
  area_names text[] not null default '{}',
  specialties text[] not null default '{}',
  status text not null default 'pending' check (status in ('pending','approved','rejected','hidden')),
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.agencies enable row level security;
-- RPCs: bk_public_agencies(), bk_agency_get(p_id), bk_agency_mine(p_token), bk_agency_save(p_token, ...),
--       bk_admin_agencies(p_token), bk_admin_agency_set(p_token, p_id, p_status, p_verified)
-- (full bodies applied through the Supabase migration "agencies_directory" on 2026-09-07)

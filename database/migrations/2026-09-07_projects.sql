-- New projects (off-plan / under construction, sold with payment plans) and their leads.
-- Applied through the Supabase migration "new_projects" on 2026-09-07.
create table if not exists public.projects (
  id bigserial primary key,
  name text not null,
  developer_user_id uuid references public.users(id) on delete set null,
  developer_name text,
  gov_name text, area_name text, address text, lat numeric, lng numeric,
  description text,
  status text not null default 'soon' check (status in ('soon','construction','handover','ready')),
  delivery text,
  price_from integer,
  down_pct integer, months integer, handover_pct integer,
  photos jsonb not null default '[]',
  units jsonb not null default '[]',   -- [{type, area_m2, rooms, price_usd, count}]
  plans jsonb not null default '[]',   -- [{name, down_pct, months, handover_pct}]
  featured boolean not null default false,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.project_leads (
  id bigserial primary key,
  project_id bigint references public.projects(id) on delete cascade,
  name text, phone text, unit text, plan text, note text,
  handled boolean not null default false,
  created_at timestamptz not null default now()
);
-- RPCs: bk_public_projects(), bk_project_get(p_id), bk_project_lead(p_project,p_name,p_phone,p_unit,p_plan,p_note),
--       bk_admin_projects(p_token), bk_admin_project_save(p_token,p_id,p_data jsonb), bk_admin_project_delete(p_token,p_id),
--       bk_admin_project_leads(p_token), bk_admin_project_lead_set(p_token,p_id,p_handled)

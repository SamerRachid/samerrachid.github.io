-- Balkoun · 2026-10-02 · "مناطق مقترحة": a staging list of neighbourhoods that are not in `areas` yet.
-- Filled by (1) a one-off OpenStreetMap import per governorate, (2) the intake bot every time a sender names a place the
-- taxonomy lacks (mentions counted), (3) the admin by hand. Nothing reaches the public lists until an admin approves it
-- in the panel (المناطق tab) — approve = insert into areas (or fill lat/lng of an existing area for kind 'geo').

create table if not exists public.area_suggestions (
  id bigserial primary key,
  governorate_id int not null references governorates(id) on delete cascade,
  name_ar text not null,
  name_en text,
  lat numeric, lng numeric,
  kind text not null default 'new' check (kind in ('new','geo')),       -- new area, or coordinates for an existing one
  area_id int references areas(id) on delete cascade,                   -- kind 'geo': the area to fill
  source text not null default 'bot' check (source in ('osm','bot','admin')),
  place text,                                                           -- OSM place tag (suburb, village…)
  osm_ref text,
  mentions int not null default 1,
  sample text,                                                          -- bot: the message snippet that named it
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists area_suggestions_uniq on public.area_suggestions (governorate_id, kind, lower(regexp_replace(name_ar, '[\sً-ْـ]+', '', 'g'))) where status = 'pending';
alter table public.area_suggestions enable row level security;

-- same name folding the site uses (ال prefix, hamza forms, ta marbuta, alef maqsura, diacritics)
create or replace function public.bk_area_norm(p text) returns text language sql immutable as $$
  select lower(trim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p,''), '[ً-ْـ]', '', 'g'), '^\s*ال', ''), '[أإآ]', 'ا', 'g'), 'ة', 'ه', 'g'), 'ى', 'ي', 'g')));
$$;

-- the bot: a place named in a message that is not in the governorate's list
create or replace function public.bk_intake_area_suggest(p_gov int, p_name text, p_sample text default null) returns json
language plpgsql security definer set search_path to 'public' as $$
declare nm text; r area_suggestions;
begin
  nm := trim(coalesce(p_name,''));
  if p_gov is null or length(nm) < 2 or length(nm) > 60 or nm !~ '[؀-ۿ]' then return json_build_object('ok', false); end if;
  if exists (select 1 from areas a where a.governorate_id = p_gov and bk_area_norm(a.name_ar) = bk_area_norm(nm)) then return json_build_object('ok', false, 'exists', true); end if;
  select * into r from area_suggestions where governorate_id = p_gov and kind = 'new' and status = 'pending' and bk_area_norm(name_ar) = bk_area_norm(nm);
  if r.id is not null then
    update area_suggestions set mentions = mentions + 1, sample = coalesce(sample, left(p_sample, 200)), updated_at = now() where id = r.id;
    return json_build_object('ok', true, 'id', r.id, 'mentions', r.mentions + 1);
  end if;
  if exists (select 1 from area_suggestions where governorate_id = p_gov and status = 'rejected' and bk_area_norm(name_ar) = bk_area_norm(nm)) then return json_build_object('ok', false, 'rejected', true); end if;
  insert into area_suggestions (governorate_id, name_ar, source, sample) values (p_gov, nm, 'bot', left(p_sample, 200)) returning * into r;
  return json_build_object('ok', true, 'id', r.id, 'mentions', 1);
end $$;
grant execute on function public.bk_intake_area_suggest(int, text, text) to service_role;

-- panel: pending suggestions of one country (or all), with per-governorate counts
create or replace function public.bk_admin_area_suggestions(p_token text, p_country text default null) returns json
language plpgsql security definer set search_path to 'public' as $$
declare uid uuid; al text[]; cc text;
begin
  uid := bk_admin_uid(p_token); al := bk_admin_allowed(uid);
  cc := nullif(upper(trim(coalesce(p_country,''))),''); if cc = 'ALL' then cc := null; end if;
  if cc is not null and al is not null and not (cc = any(al)) then cc := al[1]; end if;
  return json_build_object(
    'items', (select coalesce(json_agg(json_build_object('id', s.id, 'governorate_id', s.governorate_id, 'name_ar', s.name_ar, 'name_en', s.name_en, 'lat', s.lat, 'lng', s.lng,
                'kind', s.kind, 'area_id', s.area_id, 'area_name', a.name_ar, 'source', s.source, 'place', s.place, 'mentions', s.mentions, 'sample', s.sample, 'created_at', s.created_at)
              order by s.governorate_id, s.kind, s.mentions desc, s.name_ar), '[]'::json)
       from area_suggestions s join governorates g on g.id = s.governorate_id left join areas a on a.id = s.area_id
       where s.status = 'pending' and (cc is null or g.country_code = cc) and (al is null or g.country_code = any(al))),
    'counts', (select coalesce(json_object_agg(governorate_id, n), '{}'::json) from (
       select s.governorate_id, count(*) n from area_suggestions s join governorates g on g.id = s.governorate_id
        where s.status = 'pending' and (cc is null or g.country_code = cc) and (al is null or g.country_code = any(al)) group by s.governorate_id) x));
end $$;
grant execute on function public.bk_admin_area_suggestions(text, text) to anon, authenticated;

-- panel: approve (→ areas) or reject a set of suggestions
create or replace function public.bk_admin_area_suggest_apply(p_token text, p_ids bigint[], p_action text) returns json
language plpgsql security definer set search_path to 'public' as $$
declare uid uuid; s area_suggestions; n_ok int := 0; n_skip int := 0; v_slug text; new_id int; i int;
begin
  uid := bk_admin_uid(p_token);
  if p_action not in ('approve','reject') then return json_build_object('error','badaction'); end if;
  for s in select * from area_suggestions where id = any(p_ids) and status = 'pending' loop
    perform bk_admin_guard(uid, (select country_code from governorates where id = s.governorate_id));
    if p_action = 'reject' then
      update area_suggestions set status = 'rejected', updated_at = now() where id = s.id; n_ok := n_ok + 1; continue;
    end if;
    if s.kind = 'geo' then
      if s.area_id is not null and s.lat is not null then
        update areas set lat = s.lat, lng = s.lng where id = s.area_id;
        update area_suggestions set status = 'approved', updated_at = now() where id = s.id; n_ok := n_ok + 1;
      else update area_suggestions set status = 'rejected', updated_at = now() where id = s.id; n_skip := n_skip + 1; end if;
      continue;
    end if;
    -- a new area: skip if the name landed meanwhile
    if exists (select 1 from areas a where a.governorate_id = s.governorate_id and bk_area_norm(a.name_ar) = bk_area_norm(s.name_ar)) then
      update area_suggestions set status = 'rejected', updated_at = now() where id = s.id; n_skip := n_skip + 1; continue;
    end if;
    v_slug := lower(regexp_replace(regexp_replace(coalesce(nullif(trim(s.name_en),''), ar_slug(s.name_ar), ''), '[^a-z0-9-]+', '-', 'g'), '(^-+|-+$)', '', 'g'));
    if v_slug is null or v_slug = '' then v_slug := 'area'; end if;
    i := 0;
    while exists (select 1 from areas a where a.governorate_id = s.governorate_id and a.slug = v_slug || case when i > 0 then '-' || i else '' end) loop i := i + 1; end loop;
    if i > 0 then v_slug := v_slug || '-' || i; end if;
    insert into areas (governorate_id, name_ar, name_en, slug, kind, enabled, sort_order, lat, lng)
      values (s.governorate_id, trim(s.name_ar), nullif(trim(coalesce(s.name_en,'')),''), v_slug, case when s.place in ('village','hamlet') then 'village' when s.place = 'town' then 'city' else 'area' end, true, 100, s.lat, s.lng)
      returning id into new_id;
    update area_suggestions set status = 'approved', area_id = new_id, updated_at = now() where id = s.id; n_ok := n_ok + 1;
  end loop;
  return json_build_object('ok', true, 'done', n_ok, 'skipped', n_skip);
end $$;
grant execute on function public.bk_admin_area_suggest_apply(text, bigint[], text) to anon, authenticated;

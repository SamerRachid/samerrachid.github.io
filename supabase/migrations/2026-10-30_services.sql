-- 2026-10-30 · «خدمات العقار»: a directory of the people a buyer or tenant needs after the listing (renovation, plumbers,
-- electricians, solar, AC, aluminium windows, kitchens, carpenters, moving, cleaning …). A provider registers from his
-- Balkoun account (or the owner adds him in the panel); nobody shows before the owner approves. Contact is WhatsApp/phone,
-- straight to the provider. Both tables are closed to direct reads: everything goes through the functions below.

create table if not exists public.service_cats (
  slug text primary key,
  name_ar text not null, name_en text, grp text not null, icon text,
  sort integer not null default 100, enabled boolean not null default true
);
alter table public.service_cats enable row level security;

insert into public.service_cats (slug, name_ar, name_en, grp, icon, sort) values
  ('renovation','إكساء وترميم','Renovation','finish','roller',10),
  ('painting','دهان','Painting','finish','brush',20),
  ('tiles','بلاط وسيراميك','Tiles','finish','tiles',30),
  ('gypsum','جبس وديكور','Gypsum & decor','finish','decor',40),
  ('interior','تصميم داخلي','Interior design','finish','sofa',50),
  ('carpentry','نجارة','Carpentry','craft','saw',60),
  ('aluminium','ألمنيوم وشبابيك','Aluminium & windows','craft','window',70),
  ('ironwork','حدادة وحمايات','Ironwork & grilles','craft','grille',80),
  ('kitchens','مطابخ','Kitchens','craft','kitchen',90),
  ('plumbing','سباك','Plumbing','repair','pipe',100),
  ('electric','كهربائي','Electrician','repair','bolt',110),
  ('solar','طاقة شمسية وبطاريات','Solar & batteries','repair','sun',120),
  ('ac','تكييف وتبريد','Air conditioning','repair','snow',130),
  ('water','خزانات ومضخات مياه','Water tanks & pumps','repair','drop',140),
  ('roofing','عزل أسطح','Roof insulation','repair','roof',150),
  ('moving','نقل أثاث','Moving','move','truck',160),
  ('cleaning','تنظيف','Cleaning','move','sparkle',170),
  ('pest','مكافحة حشرات','Pest control','move','bug',180)
on conflict (slug) do nothing;

create table if not exists public.service_providers (
  id bigserial primary key,
  user_id uuid unique references public.users(id) on delete set null,
  name text not null, contact_person text, phone text, whatsapp text, description text,
  logo_url text, photos jsonb not null default '[]'::jsonb,
  cats text[] not null default '{}', gov_names text[] not null default '{}', area_names text[] not null default '{}',
  status text not null default 'pending' check (status in ('pending','approved','rejected','hidden')),
  verified boolean not null default false, featured_until timestamptz,
  country_code text not null default 'SY', created_by uuid,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.service_providers enable row level security;
create index if not exists service_providers_live on public.service_providers (country_code, status);

-- what visitors see: the categories that are on, and the approved providers (featured first)
create or replace function public.bk_public_services(p_country text default null)
returns json language sql stable security definer set search_path to 'public' as $$
  select json_build_object(
    'cats', coalesce((select json_agg(json_build_object('slug', c.slug, 'name_ar', c.name_ar, 'name_en', c.name_en, 'grp', c.grp, 'icon', c.icon) order by c.sort, c.slug)
                      from service_cats c where c.enabled), '[]'::json),
    'providers', coalesce((select json_agg(json_build_object('id', s.id, 'name', s.name, 'contact_person', s.contact_person, 'phone', s.phone, 'whatsapp', s.whatsapp,
                      'description', s.description, 'logo_url', s.logo_url, 'photos', s.photos, 'cats', s.cats, 'gov_names', s.gov_names, 'area_names', s.area_names,
                      'verified', s.verified, 'featured', coalesce(s.featured_until > now(), false), 'since', s.created_at)
                      order by coalesce(s.featured_until > now(), false) desc, s.verified desc, s.updated_at desc)
                      from service_providers s where s.status = 'approved' and s.country_code = coalesce(p_country,'SY')), '[]'::json))
$$;
grant execute on function public.bk_public_services(text) to anon, authenticated;

-- a member's own provider card
create or replace function public.bk_service_mine(p_token text)
returns json language plpgsql stable security definer set search_path to 'public', 'extensions' as $$
declare uid uuid; r service_providers;
begin
  uid := bk_member_uid(p_token); if uid is null then return null; end if;
  select * into r from service_providers where user_id = uid; if r.id is null then return null; end if;
  return row_to_json(r);
end $$;
grant execute on function public.bk_service_mine(text) to anon, authenticated;

-- a member registers / edits his card; a new card and every change wait for the owner's approval (a hidden card stays hidden)
create or replace function public.bk_service_save(p_token text, p_data jsonb)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare uid uuid; r service_providers; v_cats text[];
begin
  uid := bk_member_uid(p_token);
  if uid is null then raise exception 'not signed in'; end if; perform bk_require_verified(uid);
  if coalesce(trim(p_data->>'name'),'') = '' then return json_build_object('error','noname'); end if;
  select coalesce(array_agg(x), '{}') into v_cats from jsonb_array_elements_text(coalesce(p_data->'cats','[]'::jsonb)) x where x in (select slug from service_cats);
  if cardinality(v_cats) = 0 then return json_build_object('error','nocat'); end if;
  if coalesce(trim(p_data->>'phone'),'') = '' and coalesce(trim(p_data->>'whatsapp'),'') = '' then return json_build_object('error','nophone'); end if;
  insert into service_providers (user_id, name, contact_person, phone, whatsapp, description, logo_url, photos, cats, gov_names, area_names, country_code)
  values (uid, left(trim(p_data->>'name'),120), nullif(left(trim(coalesce(p_data->>'contact_person','')),80),''), nullif(trim(coalesce(p_data->>'phone','')),''),
          nullif(trim(coalesce(p_data->>'whatsapp','')),''), nullif(left(trim(coalesce(p_data->>'description','')),1500),''), nullif(p_data->>'logo_url',''),
          coalesce(p_data->'photos','[]'::jsonb), v_cats,
          coalesce(array(select jsonb_array_elements_text(coalesce(p_data->'gov_names','[]'::jsonb))), '{}'),
          coalesce(array(select jsonb_array_elements_text(coalesce(p_data->'area_names','[]'::jsonb))), '{}'),
          coalesce(nullif(p_data->>'country',''), (select coalesce(country,'SY') from users where id = uid), 'SY'))
  on conflict (user_id) do update set name = excluded.name, contact_person = excluded.contact_person, phone = excluded.phone, whatsapp = excluded.whatsapp,
     description = excluded.description, logo_url = excluded.logo_url, photos = excluded.photos, cats = excluded.cats, gov_names = excluded.gov_names,
     area_names = excluded.area_names, updated_at = now(),
     status = case when service_providers.status = 'hidden' then 'hidden' else 'pending' end   -- owner: every change waits for his approval again
  returning * into r;
  return row_to_json(r);
end $$;
grant execute on function public.bk_service_save(text,jsonb) to anon, authenticated;

-- the panel: every card (pending first) and every category
create or replace function public.bk_admin_services(p_token text, p_country text)
returns json language plpgsql stable security definer set search_path to 'public', 'extensions' as $$
declare uid uuid; v_cc text := upper(coalesce(nullif(p_country,''),'SY'));
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['agencies']::text[], 'bk_admin_services', null, false, '', v_cc);
  return json_build_object(
    'cats', coalesce((select json_agg(row_to_json(c) order by c.sort, c.slug) from service_cats c), '[]'::json),
    'providers', coalesce((select json_agg(json_build_object('row', row_to_json(s), 'member', (select json_build_object('name', trim(u.name||' '||coalesce(u.family_name,'')), 'phone', u.phone, 'member_no', u.member_no) from users u where u.id = s.user_id))
                      order by (s.status = 'pending') desc, s.updated_at desc)
                      from service_providers s where s.country_code = v_cc), '[]'::json));
end $$;
grant execute on function public.bk_admin_services(text,text) to anon, authenticated;

-- the panel adds or edits a card (status, verified, featured days included); p_id null = new card without an account
create or replace function public.bk_admin_service_save(p_token text, p_country text, p_id bigint, p_data jsonb)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare uid uuid; v_cc text := upper(coalesce(nullif(p_country,''),'SY')); r service_providers; v_cats text[];
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['agencies']::text[], 'bk_admin_service_save', v_cc, true, left(coalesce(p_id::text,'new'),300), v_cc);
  perform bk_admin_guard(uid, v_cc);
  if p_data ? 'cats' then select coalesce(array_agg(x), '{}') into v_cats from jsonb_array_elements_text(p_data->'cats') x where x in (select slug from service_cats); end if;
  if p_id is null then
    if coalesce(trim(p_data->>'name'),'') = '' then return json_build_object('error','noname'); end if;
    insert into service_providers (name, country_code, created_by, status) values (left(trim(p_data->>'name'),120), v_cc, uid, 'approved') returning * into r;
    p_id := r.id;
  end if;
  update service_providers set
    name = coalesce(nullif(left(trim(p_data->>'name'),120),''), name),
    contact_person = case when p_data ? 'contact_person' then nullif(trim(p_data->>'contact_person'),'') else contact_person end,
    phone = case when p_data ? 'phone' then nullif(trim(p_data->>'phone'),'') else phone end,
    whatsapp = case when p_data ? 'whatsapp' then nullif(trim(p_data->>'whatsapp'),'') else whatsapp end,
    description = case when p_data ? 'description' then nullif(left(trim(p_data->>'description'),1500),'') else description end,
    logo_url = case when p_data ? 'logo_url' then nullif(p_data->>'logo_url','') else logo_url end,
    photos = case when p_data ? 'photos' then coalesce(p_data->'photos','[]'::jsonb) else photos end,
    cats = coalesce(v_cats, cats),
    gov_names = case when p_data ? 'gov_names' then coalesce(array(select jsonb_array_elements_text(p_data->'gov_names')), '{}') else gov_names end,
    area_names = case when p_data ? 'area_names' then coalesce(array(select jsonb_array_elements_text(p_data->'area_names')), '{}') else area_names end,
    status = case when p_data->>'status' in ('pending','approved','rejected','hidden') then p_data->>'status' else status end,
    verified = coalesce((p_data->>'verified')::boolean, verified),
    featured_until = case when p_data ? 'featured_days' then (case when coalesce((p_data->>'featured_days')::int,0) > 0 then now() + make_interval(days => (p_data->>'featured_days')::int) else null end) else featured_until end,
    updated_at = now()
  where id = p_id and country_code = v_cc returning * into r;
  if r.id is null then return json_build_object('error','notfound'); end if;
  return json_build_object('ok', true, 'id', r.id);
end $$;
grant execute on function public.bk_admin_service_save(text,text,bigint,jsonb) to anon, authenticated;

-- the panel switches a category on/off, renames or reorders it, or adds a new one
create or replace function public.bk_admin_service_cat_save(p_token text, p_slug text, p_data jsonb)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['agencies']::text[], 'bk_admin_service_cat_save', null, true, left(coalesce(p_slug,''),300), null);
  if coalesce(p_slug,'') !~ '^[a-z][a-z0-9_]{1,30}$' then return json_build_object('error','badslug'); end if;
  insert into service_cats (slug, name_ar, name_en, grp, icon, sort, enabled)
  values (p_slug, coalesce(nullif(trim(p_data->>'name_ar'),''), p_slug), nullif(trim(coalesce(p_data->>'name_en','')),''), coalesce(nullif(p_data->>'grp',''),'repair'),
          nullif(p_data->>'icon',''), coalesce((p_data->>'sort')::int, 500), coalesce((p_data->>'enabled')::boolean, true))
  on conflict (slug) do update set
    name_ar = coalesce(nullif(trim(p_data->>'name_ar'),''), service_cats.name_ar),
    name_en = case when p_data ? 'name_en' then nullif(trim(p_data->>'name_en'),'') else service_cats.name_en end,
    grp = coalesce(nullif(p_data->>'grp',''), service_cats.grp),
    sort = coalesce((p_data->>'sort')::int, service_cats.sort),
    enabled = coalesce((p_data->>'enabled')::boolean, service_cats.enabled);
  return json_build_object('ok', true);
end $$;
grant execute on function public.bk_admin_service_cat_save(text,text,jsonb) to anon, authenticated;

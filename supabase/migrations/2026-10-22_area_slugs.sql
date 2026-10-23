-- Area URL slugs (owner, 2026-10-22, pending item 12).
-- The bug: bk_admin_area_suggest_apply / bk_admin_area_save stripped every character outside [a-z0-9-] BEFORE lowercasing,
-- so each capital letter became a dash: «Judaydat al-Wadi» → udaydat-al--adi, «Hama» → ama (3,548 Syrian areas).
-- Others were built from the Arabic name with no vowels (hlbwny, krm-lwz).
-- Fix: one latin slug builder (lowercase first, accents folded), both functions use it, the broken slugs are rebuilt
-- from the English name, and every replaced slug is kept in areas.old_slugs so the page generator can leave a redirect
-- at the old address (Google already knows some of them).

create or replace function public.bk_slug_latin(txt text) returns text
language sql immutable set search_path to 'public' as $$
  select nullif(left(regexp_replace(regexp_replace(
    translate(lower(coalesce(txt,'')),
      'āáàâäãåīíìîïūúùûüēéèêëōóòôöõçşšğžñýÿḥṣṭḍẓṯḏġḳṛṇṃʿʾ''’`',
      'aaaaaaaiiiiiuuuuueeeeeoooooocssgznyyhstdztdgkrnm'),
    '[^a-z0-9]+', '-', 'g'), '(^-+|-+$)', '', 'g'), 60), '')
$$;

-- the slug an area gets when none is typed: its English name, else the Arabic one transliterated
create or replace function public.bk_area_slug(p_en text, p_ar text) returns text
language sql immutable set search_path to 'public' as $$
  select coalesce(bk_slug_latin(split_part(p_en, '/', 1)), bk_slug_latin(ar_slug(p_ar)), 'area')   -- «A / B» names: the first one
$$;

alter table public.areas add column if not exists old_slugs text[] not null default '{}';

-- 1. the data: rebuild the broken slugs (only Syria; the Gulf acronyms jbr / jvc / jlt stay as they are).
--    Set-based (one trigger run per statement, not per row); a temporary slug first so no swap trips the unique index.
create temporary table _slugfix on commit drop as
with c as (
  select a.id, a.governorate_id gid, a.slug old, bk_slug_latin(split_part(a.name_en, '/', 1)) base
  from areas a join governorates g on g.id = a.governorate_id
  where coalesce(g.country_code,'SY') = 'SY' and bk_slug_latin(a.name_en) is not null
    and a.slug is distinct from bk_slug_latin(split_part(a.name_en, '/', 1))
    and (
      -- made by the old bug from this very English name (optionally with a -N suffix added for uniqueness)
      regexp_replace(a.slug, '-[0-9]+$', '') = lower(regexp_replace(regexp_replace(a.name_en, '[^a-z0-9-]+', '-', 'g'), '(^-+|-+$)', '', 'g'))
      or a.slug ~ '--' or a.slug ~ '(^-|-$)'
      -- consonants only (from the Arabic name)
      or replace(a.slug, '-', '') !~ '[aeiou]'
    )
), r as (
  select c.*, row_number() over (partition by gid, base order by id) rn,
         exists (select 1 from areas x where x.governorate_id = c.gid and x.slug = c.base and x.id not in (select id from c)) taken
  from c
)
select id, old, case when rn = 1 and not taken then base else left(base, 56) || '-' || (rn + case when taken then 1 else 0 end) end as slug from r;

update areas a set slug = 'tmp-slug-' || a.id from _slugfix f where f.id = a.id;
update areas a set slug = f.slug,
       old_slugs = case when f.old is null or f.old = any(a.old_slugs) then a.old_slugs else a.old_slugs || f.old end
  from _slugfix f where f.id = a.id;

-- 2. saving an area in the admin: lowercase first; when the slug changes, the old one is kept for the redirect
create or replace function public.bk_admin_area_save(p_token text, p_row jsonb)
 returns json language plpgsql security definer set search_path to 'public'
as $function$ declare uid uuid; v_id int; v_slug text; r areas; v_old text; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['geo']::text[], 'bk_admin_area_save', (select country_code from governorates where id=coalesce(nullif(p_row->>'governorate_id','')::bigint,(select governorate_id from areas where id=nullif(p_row->>'id','')::bigint))), true, left(coalesce(p_row::text,''),300), (select country_code from governorates where id=coalesce(nullif(p_row->>'governorate_id','')::bigint,(select governorate_id from areas where id=nullif(p_row->>'id','')::bigint)))); perform bk_admin_guard(uid, (select country_code from governorates where id = (p_row->>'governorate_id')::int)); v_id := nullif(p_row->>'id','')::int;
  v_slug := bk_slug_latin(nullif(trim(coalesce(p_row->>'slug','')),''));
  if v_slug is null then v_slug := bk_area_slug(p_row->>'name_en', p_row->>'name_ar'); end if;
  if exists (select 1 from areas a where a.governorate_id = (p_row->>'governorate_id')::int and a.slug = v_slug and (v_id is null or a.id <> v_id)) then raise exception 'slug_taken'; end if;
  if v_id is null then insert into areas (governorate_id, name_ar, name_en, slug, kind, enabled, sort_order, lat, lng) values ((p_row->>'governorate_id')::int, trim(p_row->>'name_ar'), nullif(trim(coalesce(p_row->>'name_en','')),''), v_slug, coalesce(nullif(p_row->>'kind',''),'area'), coalesce((p_row->>'enabled')::boolean, true), coalesce((p_row->>'sort_order')::int, 100), nullif(p_row->>'lat','')::numeric, nullif(p_row->>'lng','')::numeric) returning * into r;
  else select slug into v_old from areas where id = v_id;
    update areas set governorate_id = coalesce((p_row->>'governorate_id')::int, governorate_id), name_ar = coalesce(nullif(trim(p_row->>'name_ar'),''), name_ar), name_en = nullif(trim(coalesce(p_row->>'name_en','')),''), slug = v_slug,
      old_slugs = array_remove(case when v_old is not null and v_old <> v_slug and not (v_old = any(old_slugs)) then old_slugs || v_old else old_slugs end, v_slug),
      kind = coalesce(nullif(p_row->>'kind',''), kind), enabled = coalesce((p_row->>'enabled')::boolean, enabled), sort_order = coalesce((p_row->>'sort_order')::int, sort_order), lat = nullif(p_row->>'lat','')::numeric, lng = nullif(p_row->>'lng','')::numeric where id = v_id returning * into r; end if; return row_to_json(r); end $function$;

-- 3. approving suggested areas: same builder
create or replace function public.bk_admin_area_suggest_apply(p_token text, p_ids bigint[], p_action text)
 returns json language plpgsql security definer set search_path to 'public'
as $function$
declare uid uuid; s area_suggestions; n_ok int := 0; n_skip int := 0; v_slug text; new_id int; i int;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['geo']::text[], 'bk_admin_area_suggest_apply', null, true, left(coalesce(p_ids::text,''),300), null);
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
    if exists (select 1 from areas a where a.governorate_id = s.governorate_id and bk_area_norm(a.name_ar) = bk_area_norm(s.name_ar)) then
      update area_suggestions set status = 'rejected', updated_at = now() where id = s.id; n_skip := n_skip + 1; continue;
    end if;
    v_slug := bk_area_slug(s.name_en, s.name_ar);
    i := 0;
    while exists (select 1 from areas a where a.governorate_id = s.governorate_id and a.slug = v_slug || case when i > 0 then '-' || i else '' end) loop i := i + 1; end loop;
    if i > 0 then v_slug := v_slug || '-' || i; end if;
    insert into areas (governorate_id, name_ar, name_en, slug, kind, enabled, sort_order, lat, lng)
      values (s.governorate_id, trim(s.name_ar), nullif(trim(coalesce(s.name_en,'')),''), v_slug, case when s.place in ('village','hamlet') then 'village' when s.place = 'town' then 'city' else 'area' end, true, 100, s.lat, s.lng)
      returning id into new_id;
    update area_suggestions set status = 'approved', area_id = new_id, updated_at = now() where id = s.id; n_ok := n_ok + 1;
    -- listings published meanwhile with this place written as the landmark now get the area
    update listings set area_id = new_id where governorate_id = s.governorate_id and area_id is null and landmark is not null and position(bk_area_norm(s.name_ar) in bk_area_norm(landmark)) > 0;
  end loop;
  return json_build_object('ok', true, 'done', n_ok, 'skipped', n_skip);
end $function$;

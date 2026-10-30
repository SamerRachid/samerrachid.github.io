-- 2026-10-29 · areas from the WhatsApp intake  (applied by the owner in the Supabase SQL editor, verified the same day)
-- (1) bk_intake_publish looked areas up by name without checking `enabled`, so a merged-away duplicate (الزهراء 188)
--     could win over the live one (150). Exact and fuzzy lookups now take enabled areas only.
-- (2) A bot suggestion the admin approved and linked to an area (area_suggestions.status='approved', area_id set,
--     e.g. «سيدي مقدام» → سيدي مقداد) now works as an alias: the listing gets that area, and its governorate when the
--     alias pointed across (بيلا in دمشق → ببيلا in ريف دمشق). bk_intake_area_suggest no longer re-proposes such a name.
-- (3) Safety net for every path (form, admin, intake): a listing written with a disabled area is moved to its
--     enabled twin in the same governorate (same normalized name).
-- The two intake functions are patched line by line; if a line is not found the whole block aborts and nothing changes.
do $do$
declare d text; o text; n text;
begin
  d := pg_get_functiondef('public.bk_intake_publish'::regproc);
  o := $q$    select id into aid from areas where governorate_id = gid and (name_ar = aname or lower(coalesce(name_en,'')) = lower(aname)) limit 1;$q$;
  n := $q$    select id into aid from areas where governorate_id = gid and enabled and (name_ar = aname or lower(coalesce(name_en,'')) = lower(aname)) order by id limit 1;
    if aid is null then select x.id into aid from area_suggestions s join areas x on x.id = s.area_id and x.enabled where s.status = 'approved' and s.governorate_id = gid and bk_area_norm(s.name_ar) = bk_area_norm(aname) order by s.mentions desc limit 1;
      if aid is not null then select governorate_id into gid from areas where id = aid; end if; end if;$q$;
  if position(o in d) = 0 then raise exception 'bk_intake_publish: exact lookup line not found'; end if;
  d := replace(d, o, n);
  o := $q$    if aid is null then select id into aid from areas where governorate_id = gid and (name_ar like '%'||aname||'%' or aname like '%'||name_ar||'%') order by length(name_ar) limit 1; end if;$q$;
  n := $q$    if aid is null then select id into aid from areas where governorate_id = gid and enabled and (name_ar like '%'||aname||'%' or aname like '%'||name_ar||'%') order by length(name_ar) limit 1; end if;$q$;
  if position(o in d) = 0 then raise exception 'bk_intake_publish: fuzzy lookup line not found'; end if;
  d := replace(d, o, n);
  execute d;

  d := pg_get_functiondef('public.bk_intake_area_suggest'::regproc);
  o := $q$  select * into r from area_suggestions where governorate_id = p_gov and kind = 'new' and status = 'pending'$q$;
  n := $q$  if exists (select 1 from area_suggestions s join areas x on x.id = s.area_id and x.enabled where s.governorate_id = p_gov and s.status = 'approved' and bk_area_norm(s.name_ar) = bk_area_norm(nm)) then return json_build_object('ok', false, 'exists', true, 'alias', true); end if;
  select * into r from area_suggestions where governorate_id = p_gov and kind = 'new' and status = 'pending'$q$;
  if position(o in d) = 0 then raise exception 'bk_intake_area_suggest: pending lookup line not found'; end if;
  d := replace(d, o, n);
  execute d;
end $do$;

create or replace function public.bk_trg_listing_area_live()
returns trigger language plpgsql set search_path to 'public' as $$
declare a areas; twin int;
begin
  if new.area_id is null then return new; end if;
  select * into a from areas where id = new.area_id;
  if a.id is null or a.enabled is not false then return new; end if;
  select x.id into twin from areas x
   where x.id <> a.id and x.enabled is not false and x.governorate_id in (a.governorate_id, new.governorate_id)
     and bk_area_norm(x.name_ar) = bk_area_norm(a.name_ar)
   order by (x.governorate_id = new.governorate_id) desc, x.id limit 1;
  if twin is not null then new.area_id := twin; end if;
  return new;
end $$;
drop trigger if exists trg_listing_area_live on public.listings;
create trigger trg_listing_area_live before insert or update of area_id on public.listings
  for each row execute function public.bk_trg_listing_area_live();

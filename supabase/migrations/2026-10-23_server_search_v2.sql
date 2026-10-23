-- Server-side search, step 2 (owner said "do it" 2026-10-23: the full switch, built by day, published at night after his OK).
-- Everything the site computed from the full catalogue in the browser now has a server function:
--   bk_search2         one page of results + (optionally) every hit as a slim map pin + the condition facet counts
--   bk_listing_stats   live counts per governorate and per area (field menus, areas page, country map)
--   bk_wanted_matches  matching listings per «wanted» request (the client rule of wantedMatches())
-- New functions only; bk_search (step 1) and everything else stay as they are. The site uses these only while the
-- panel switch «server_search» is on.

-- the filter object F of the page, parsed once
do $$ begin
  if not exists (select 1 from pg_type where typname = 'bk_srch_p' and typnamespace = 'public'::regnamespace) then
    create type public.bk_srch_p as (
      govs text[], areas text[], tbs text[], cd text, furn text, rper text, tlist text[], sec text, deal text,
      pmin numeric, pmax numeric, rsel int[], own_only boolean, share_only boolean, words text[],
      land text[], comm text[], rooms_max int, uid uuid, feat boolean, excl bigint, min_views int);
  end if;
end $$;

create or replace function public.bk_srch_parse(p_f jsonb, p_land text[], p_comm text[], p_rooms_max int)
returns public.bk_srch_p language plpgsql stable set search_path to 'public','extensions' as $fn$
declare f jsonb := coalesce(p_f, '{}'::jsonb); p public.bk_srch_p;
begin
  p.govs  := case when jsonb_typeof(f->'govs')='array'  and jsonb_array_length(f->'govs')>0  then array(select jsonb_array_elements_text(f->'govs'))
                  when nullif(f->>'g','') is not null then array[f->>'g'] end;
  p.areas := case when jsonb_typeof(f->'areas')='array' and jsonb_array_length(f->'areas')>0 then array(select jsonb_array_elements_text(f->'areas'))
                  when nullif(f->>'a','') is not null then array[f->>'a'] end;
  p.tbs   := case when jsonb_typeof(f->'tbs')='array'   and jsonb_array_length(f->'tbs')>0   then array(select jsonb_array_elements_text(f->'tbs'))
                  when nullif(f->>'tb','') is not null then array[f->>'tb'] end;
  p.tlist := case when jsonb_typeof(f->'types')='array' and jsonb_array_length(f->'types')>0 then array(select jsonb_array_elements_text(f->'types'))
                  when nullif(f->>'t','') is not null then array[f->>'t'] end;
  p.rsel  := case when jsonb_typeof(f->'rooms')='array' and jsonb_array_length(f->'rooms')>0 then array(select (jsonb_array_elements_text(f->'rooms'))::int) end;
  p.deal := nullif(f->>'deal',''); p.sec := nullif(f->>'sec',''); p.cd := nullif(f->>'cd','');
  p.furn := nullif(f->>'furn',''); p.rper := nullif(f->>'rentalPeriod','');
  p.pmin := nullif(nullif(f->>'pmin',''),'0')::numeric; p.pmax := nullif(nullif(f->>'pmax',''),'0')::numeric;
  p.own_only := coalesce((f->>'ownerOnly')::boolean, false); p.share_only := coalesce((f->>'shareOnly')::boolean, false);
  p.words := case when nullif(btrim(coalesce(f->>'kw','')),'') is not null then bk_kw_words(f->>'kw') end;
  if p.words is not null and cardinality(p.words) = 0 then p.words := null; end if;
  p.land := coalesce(p_land, '{}'); p.comm := coalesce(p_comm, '{}'); p.rooms_max := coalesce(p_rooms_max, 7);
  -- not search-page filters: an office's listings, featured only, one listing left out (similar), popular (views > 0)
  p.uid := nullif(f->>'uid','')::uuid; p.feat := coalesce((f->>'featured')::boolean, false);
  p.excl := nullif(f->>'exclude','')::bigint; p.min_views := nullif(f->>'minViews','')::int;
  return p;
end $fn$;

-- the same rule as passesFilter() on the page (a plain SQL body, so the planner inlines it into the query)
create or replace function public.bk_srch_ok(v public.v_listings, p public.bk_srch_p)
returns boolean language sql stable parallel safe set search_path to 'public','extensions' as $fn$
  select (p.govs  is null or v.governorate_ar = any(p.govs))
     and (p.areas is null or coalesce(v.area_ar,'') = any(p.areas))
     and (p.tbs   is null or p.deal = 'rent' or v.tabu = any(p.tbs))
     and (p.cd    is null or v.condition = p.cd)
     and (p.furn  is null or p.deal is distinct from 'rent' or (p.furn = 'yes' and coalesce(v.furnished,false)) or (p.furn = 'no' and not coalesce(v.furnished,false)) or p.furn not in ('yes','no'))
     and (p.rper  is null or p.deal is distinct from 'rent' or coalesce(v.rental_period,'yearly') = p.rper)
     and (p.tlist is null or v.property_type = any(p.tlist) or ('land' = any(p.tlist) and v.property_type = any(p.land)))
     and (p.sec   is null or (p.sec = 'land' and v.property_type = any(p.land)) or (p.sec = 'commercial' and v.property_type = any(p.comm))
                          or (p.sec = 'homes' and not (v.property_type = any(p.land)) and not (v.property_type = any(p.comm))))
     and (p.deal  is null or v.deal = p.deal)
     and (p.pmin  is null or (v.price_usd is not null and v.price_usd >= p.pmin))
     and (p.pmax  is null or (v.price_usd is not null and v.price_usd <= p.pmax))
     and (p.rsel  is null or coalesce(v.rooms,0) = any(p.rsel) or (p.rooms_max = any(p.rsel) and coalesce(v.rooms,0) >= p.rooms_max))
     and (not p.own_only or coalesce(v.by_owner,false))
     and (not p.share_only or 'متاح للمشاركة' = any(coalesce(v.amenities,'{}')))
     and (p.uid is null or v.user_id = p.uid)
     and (not p.feat or coalesce(v.is_featured,false))
     and (p.excl is null or v.id <> p.excl)
     and (p.min_views is null or coalesce(v.views,0) >= p.min_views)
     and (p.words is null or bk_kw_hit(bk_kw_norm(coalesce(v.description,'')||' '||coalesce(v.landmark,'')||' '||coalesce(v.area_ar,'')||' '||coalesce(v.governorate_ar,'')||' '||
                                                    coalesce(array_to_string(v.amenities,' '),'')||' '||coalesce(nullif(v.contact_name,''), v.owner_name, '')), p.words))
$fn$;

-- p_sort: new (featured first, newest) · lo · hi · area · views (most viewed) · recent (newest, no featured lift)
-- p_want: 'pins' = every hit as [id,lat,lng,price,m2,type,deal,gov,area,area_id,featured,cover,rooms,baths,living,deed,period]
--         in result order (the full-screen map's card shows rooms / baths / deed);
--         'cd'   = counts per condition with the condition filter itself left out (the «more» menu)
create or replace function public.bk_search2(
  p_country text, p_f jsonb, p_land text[], p_comm text[],
  p_sort text default 'new', p_offset integer default 0, p_limit integer default 24,
  p_rooms_max integer default 7, p_want text[] default '{}')
returns json language plpgsql stable security definer set search_path to 'public','extensions' as $fn$
declare
  p public.bk_srch_p; pc public.bk_srch_p; cc text := coalesce(nullif(p_country,''),'SY');
  srt text := coalesce(nullif(p_sort,''),'new'); ff boolean; lim int; off int; res jsonb;
begin
  p := bk_srch_parse(p_f, p_land, p_comm, p_rooms_max);
  ff := srt not in ('views','recent');
  lim := least(greatest(coalesce(p_limit,24),0),200); off := greatest(coalesce(p_offset,0),0);
  with hit as materialized (
    select v.id, v.lat, v.lng, v.price_usd, v.area_m2, v.property_type, v.deal, v.governorate_ar, v.area_ar, v.area_id,
           v.is_featured, v.cover_url, v.created_at, v.views, v.rooms, v.baths, v.living_rooms, v.tabu, v.rental_period
      from v_listings v
     where v.country_code = cc and v.status = 'live' and bk_srch_ok(v, p)
  ), ord as (
    select h.*, row_number() over (order by
             case when ff then coalesce(h.is_featured,false) end desc,
             case when srt = 'lo' then h.price_usd end asc nulls last,
             case when srt = 'hi' then h.price_usd end desc nulls last,
             case when srt = 'area' then h.area_m2 end desc nulls last,
             case when srt = 'views' then h.views end desc nulls last,
             h.created_at desc, h.id desc) rn
      from hit h
  )
  select jsonb_build_object(
    'total', (select count(*) from hit),
    'offset', off, 'limit', lim,
    'rows', case when lim > 0 then coalesce((select jsonb_agg(to_jsonb(x) order by o.rn) from ord o join v_listings x on x.id = o.id
                                              where o.rn > off and o.rn <= off + lim), '[]'::jsonb) else '[]'::jsonb end,
    'pins', case when 'pins' = any(coalesce(p_want,'{}')) then coalesce((select jsonb_agg(jsonb_build_array(o.id, o.lat, o.lng, o.price_usd, o.area_m2,
              o.property_type, o.deal, o.governorate_ar, o.area_ar, o.area_id, o.is_featured, o.cover_url,
              o.rooms, o.baths, o.living_rooms, o.tabu, o.rental_period) order by o.rn) from ord o), '[]'::jsonb) end)
    into res;
  if 'cd' = any(coalesce(p_want,'{}')) then
    pc := p; pc.cd := null;
    res := res || jsonb_build_object('cd', coalesce((select jsonb_object_agg(c, n) from (
             select coalesce(v.condition,'') c, count(*) n from v_listings v
              where v.country_code = cc and v.status = 'live' and bk_srch_ok(v, pc) group by 1) z), '{}'::jsonb));
  end if;
  return res::json;
end $fn$;

-- live listings per governorate and per «governorate|area»
create or replace function public.bk_listing_stats(p_country text default 'SY')
returns json language sql stable security definer set search_path to 'public' as $fn$
  with v as (select governorate_ar g, coalesce(area_ar,'') a from v_listings where country_code = coalesce(nullif(p_country,''),'SY') and status = 'live')
  select json_build_object(
    'total', (select count(*) from v),
    'g', coalesce((select json_object_agg(g, n) from (select g, count(*) n from v where g is not null group by g) x), '{}'::json),
    'a', coalesce((select json_object_agg(k, n) from (select g||'|'||a k, count(*) n from v where g is not null and a <> '' group by 1) y), '{}'::json))
$fn$;

-- per «wanted» request: how many live listings fit and the newest 12 of them — the page's own rule (wantedMatches)
create or replace function public.bk_wanted_matches(p_country text, p_ids bigint[])
returns json language sql stable security definer set search_path to 'public' as $fn$
  select coalesce(json_object_agg(w.id, json_build_object('n', m.n, 'ids', coalesce(m.ids, '{}'))), '{}'::json)
    from wanted w
    cross join lateral (
      select count(*) n, (array_agg(v.id order by v.created_at desc, v.id desc))[1:12] ids
        from v_listings v
       where v.country_code = coalesce(nullif(p_country,''),'SY') and v.status = 'live' and v.deal = w.deal
         and (coalesce(w.gov_name,'') = '' or v.governorate_ar = w.gov_name)
         and (cardinality(coalesce(nullif(w.property_types,'{}'), case when w.property_type is not null then array[w.property_type] end, '{}')) = 0
              or v.property_type = any(coalesce(nullif(w.property_types,'{}'), array[w.property_type])))
         and (cardinality(coalesce(w.area_names,'{}')) = 0 or coalesce(v.area_ar,'') = any(w.area_names))
         and (coalesce(w.budget_max,0) = 0 or v.price_usd is null or coalesce(bk_wanted_rate(w.country_code, w.currency),0) <= 0
              or v.price_usd <= w.budget_max / bk_wanted_rate(w.country_code, w.currency) * 1.1)
         and (coalesce(w.rooms_min,0) = 0 or coalesce(v.rooms,0) >= w.rooms_min)
         and (coalesce(w.area_min,0) = 0 or coalesce(v.area_m2,0) >= w.area_min)
         and (coalesce(w.tabu,'') = '' or w.deal = 'rent' or v.tabu = w.tabu)
         and (w.user_id is null or v.user_id is distinct from w.user_id)
    ) m
   where w.id = any(coalesce(p_ids,'{}'))
$fn$;

revoke all on function public.bk_search2(text,jsonb,text[],text[],text,integer,integer,integer,text[]) from public;
revoke all on function public.bk_listing_stats(text) from public;
revoke all on function public.bk_wanted_matches(text,bigint[]) from public;
grant execute on function public.bk_search2(text,jsonb,text[],text[],text,integer,integer,integer,text[]) to anon, authenticated;
grant execute on function public.bk_listing_stats(text) to anon, authenticated;
grant execute on function public.bk_wanted_matches(text,bigint[]) to anon, authenticated;

-- Home «ما يتابعه الناس هذا الأسبوع» (the only caller of sort 'views') ranked by all-time listings.views, so the same
-- listings stayed on top for weeks. Sort 'views' now ranks by distinct visitors in page_views over the last 7 days,
-- then all-time views (fills the list when few listings were seen this week). Nothing else in bk_search2 changes.
-- Undo: 2026-11-08_popular_this_week_undo.sql
CREATE OR REPLACE FUNCTION public.bk_search2(p_country text, p_f jsonb, p_land text[], p_comm text[], p_sort text DEFAULT 'new'::text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 24, p_rooms_max integer DEFAULT 7, p_want text[] DEFAULT '{}'::text[])
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  p public.bk_srch_p; pc public.bk_srch_p; cc text := coalesce(nullif(p_country,''),'SY');
  srt text := coalesce(nullif(p_sort,''),'new'); ff boolean; lim int; off int; res jsonb;
begin
  p := bk_srch_parse(p_f, p_land, p_comm, p_rooms_max);
  ff := srt not in ('views','recent');
  lim := least(greatest(coalesce(p_limit,24),0),200); off := greatest(coalesce(p_offset,0),0);
  with hit as materialized (
    select v.id, v.lat, v.lng, v.price_usd, v.area_m2, v.property_type, v.deal, v.governorate_ar, v.area_ar, v.area_id,
           v.is_featured, v.cover_url, v.created_at, v.views, v.rooms, v.baths, v.living_rooms, v.tabu, v.rental_period, v.price_local, v.price_cur
      from v_listings v
     where v.country_code = cc and v.status = 'live' and bk_srch_ok(v, p)
  ), wk as materialized (
    -- people (not page loads) who opened each listing in the last 7 days; only read for sort 'views'
    select pv.listing_id id, count(distinct coalesce(pv.visitor_id, pv.user_id::text)) n
      from page_views pv
     where srt = 'views' and pv.listing_id is not null and pv.created_at > now() - interval '7 days'
       and coalesce(pv.visitor_id, pv.user_id::text) is not null
     group by 1
  ), ord as (
    select h.*, row_number() over (order by
             case when ff then coalesce(h.is_featured,false) end desc,
             case when srt = 'lo' then h.price_usd end asc nulls last,
             case when srt = 'hi' then h.price_usd end desc nulls last,
             case when srt = 'area' then h.area_m2 end desc nulls last,
             case when srt = 'views' then coalesce(w.n,0) end desc,
             case when srt = 'views' then h.views end desc nulls last,
             h.created_at desc, h.id desc) rn
      from hit h left join wk w on w.id = h.id
  )
  select jsonb_build_object(
    'total', (select count(*) from hit),
    'offset', off, 'limit', lim,
    'rows', case when lim > 0 then coalesce((select jsonb_agg(to_jsonb(x) order by o.rn) from ord o join v_listings x on x.id = o.id
                                              where o.rn > off and o.rn <= off + lim), '[]'::jsonb) else '[]'::jsonb end,
    'pins', case when 'pins' = any(coalesce(p_want,'{}')) then coalesce((select jsonb_agg(jsonb_build_array(o.id, o.lat, o.lng, o.price_usd, o.area_m2,
              o.property_type, o.deal, o.governorate_ar, o.area_ar, o.area_id, o.is_featured, o.cover_url,
              o.rooms, o.baths, o.living_rooms, o.tabu, o.rental_period, o.price_local, o.price_cur) order by o.rn) from ord o), '[]'::jsonb) end)
    into res;
  if 'cd' = any(coalesce(p_want,'{}')) then
    pc := p; pc.cd := null;
    res := res || jsonb_build_object('cd', coalesce((select jsonb_object_agg(c, n) from (
             select coalesce(v.condition,'') c, count(*) n from v_listings v
              where v.country_code = cc and v.status = 'live' and bk_srch_ok(v, pc) group by 1) z), '{}'::jsonb));
  end if;
  return res::json;
end $function$;

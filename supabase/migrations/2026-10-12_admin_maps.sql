-- 2026-10-12: admin panel page "الخرائط" — per-area breakdown of how each live listing gets its map pin:
-- set by the poster (listings.lat/lng), inherited from the area centroid (areas.lat/lng), or not connected
-- at all (area has no centroid either). Lets the admin drop a pin for an area once, fixing every listing in
-- it at the same time (reuses the area-centroid fallback shipped earlier today).

CREATE OR REPLACE FUNCTION public.bk_admin_areas_map(p_token text, p_country text default null) RETURNS json
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x order by x.live desc, x.area) from (
    select a.id, a.name_ar as area, g.name_ar as gov, a.lat, a.lng, g.lat as gov_lat, g.lng as gov_lng,
           count(*) filter (where l.status='live') as live,
           count(*) filter (where l.status='live' and l.lat is not null and l.lng is not null) as pinned
      from listings l
      join areas a on a.id = l.area_id
      join governorates g on g.id = a.governorate_id
     where bk_scope_ok(l.country_code, sc, al)
     group by a.id, a.name_ar, g.name_ar, a.lat, a.lng, g.lat, g.lng
    ) x), '[]'::json);
end $function$;

CREATE OR REPLACE FUNCTION public.bk_admin_area_set_coords(p_token text, p_area_id int, p_lat numeric, p_lng numeric) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); if uid is null then raise exception 'not admin'; end if;
  update areas set lat=p_lat, lng=p_lng where id=p_area_id;
  return true;
end $function$;

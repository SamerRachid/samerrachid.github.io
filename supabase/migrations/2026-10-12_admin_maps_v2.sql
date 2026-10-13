-- 2026-10-12 (v2): per-listing map-connection status (for the clickable summary cards on the admin Maps
-- page), and a site-wide on/off switch for the area-centroid fallback shipped earlier today.

CREATE OR REPLACE FUNCTION public.bk_admin_listings_map_status(p_token text, p_country text default null) RETURNS json
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x) from (
    select l.id, l.ref, l.property_type, l.price_usd, a.name_ar as area, g.name_ar as gov,
      case when l.lat is not null and l.lng is not null then 'user'
           when a.lat is not null and a.lng is not null then 'balkoun'
           else 'none' end as mstatus
    from listings l
    join areas a on a.id = l.area_id
    join governorates g on g.id = a.governorate_id
    where l.status='live' and bk_scope_ok(l.country_code, sc, al)
  ) x), '[]'::json);
end $function$;

CREATE OR REPLACE FUNCTION public.bk_admin_map_fallback_get(p_country text default null) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','extensions' AS $function$
  select coalesce((extras->>'map_area_fallback_on')::boolean, true)
    from site_content where country_code = (case when p_country is null or upper(p_country)='ALL' or p_country='' then 'SY' else upper(p_country) end);
$function$;

CREATE OR REPLACE FUNCTION public.bk_admin_map_fallback_set(p_token text, p_on boolean, p_country text default null) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $function$
declare uid uuid; v_c text := case when p_country is null or upper(p_country)='ALL' or p_country='' then 'SY' else upper(p_country) end;
begin
  uid := bk_admin_uid(p_token); if uid is null then raise exception 'not admin'; end if;
  update site_content set extras = coalesce(extras,'{}'::jsonb) || jsonb_build_object('map_area_fallback_on', p_on) where country_code=v_c;
  return true;
end $function$;

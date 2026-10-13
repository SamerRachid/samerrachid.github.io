-- 2026-10-12: approximate map placement for listings that have no precise lat/lng (most of them —
-- only a handful were posted through the map picker). The client now falls back to the listing's
-- AREA centroid (areas.lat/lng, already populated for ~80% of areas) plus a small deterministic
-- spiral offset per listing so several listings in the same area don't stack on one pin. This is a
-- read-only reference list (id -> lat/lng), small and public, no auth needed.
CREATE OR REPLACE FUNCTION public.bk_area_coords() RETURNS json
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','extensions' AS $function$
  select coalesce(json_agg(json_build_object('id', id, 'lat', lat, 'lng', lng)), '[]'::json)
    from areas where lat is not null and lng is not null and enabled;
$function$;

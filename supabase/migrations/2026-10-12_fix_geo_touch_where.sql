-- 2026-10-12: bk_geo_touch() (fires on any insert/update/delete to areas/governorates, bumping
-- site_content.extras.geo_v so clients know to refetch) ran its UPDATE with no WHERE clause at all.
-- The database now rejects bare UPDATEs outright ("UPDATE requires a WHERE clause"), which silently
-- broke every area/governorate edit in the admin panel, not just the new per-area map picker. The
-- intent was always "touch every country's site_content row" — `where true` makes that explicit.
CREATE OR REPLACE FUNCTION public.bk_geo_touch() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
begin
  update public.site_content
     set extras = coalesce(extras, '{}'::jsonb)
               || jsonb_build_object('geo_v', (extract(epoch from clock_timestamp()) * 1000)::bigint)
   where true;
  return null;
end $function$;

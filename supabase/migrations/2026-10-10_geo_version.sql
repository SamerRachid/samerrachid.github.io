-- 2026-10-10: geography version stamp.
-- Visitors cache bk_geo() (~400 KB) in localStorage for 24 h (loadGeo in index.html, added 2026-10-09 to stop
-- re-downloading it on every page load). Side effect found the next day: an area the owner added in the admin
-- (العدوية, Homs) was invisible to visitors — and to the owner's own phone — until that day passed.
-- Fix: any change to governorates/areas bumps site_content.extras.geo_v on every country row (site_content is read
-- on every page load anyway); the client refetches the geography as soon as the stamp it cached no longer matches.
create or replace function public.bk_geo_touch() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.site_content
     set extras = coalesce(extras, '{}'::jsonb)
               || jsonb_build_object('geo_v', (extract(epoch from clock_timestamp()) * 1000)::bigint);
  return null;
end $$;
revoke all on function public.bk_geo_touch() from public;

create trigger bk_geo_touch_areas after insert or update or delete on public.areas
  for each statement execute function public.bk_geo_touch();
create trigger bk_geo_touch_govs after insert or update or delete on public.governorates
  for each statement execute function public.bk_geo_touch();

-- seed the stamp now, so every existing visitor cache (which carries no stamp yet) refetches once
update public.site_content
   set extras = coalesce(extras, '{}'::jsonb)
             || jsonb_build_object('geo_v', (extract(epoch from clock_timestamp()) * 1000)::bigint);

-- 2026-10-13: deleting a featured listing left its homepage square behind, empty.
-- ad_slots.linked_listing_id is ON DELETE SET NULL, so the free-feature reward square (which has no media of
-- its own — it only ever showed the listing's photos) stayed enabled with no listing and no image, and
-- bk_public_ad_slots still handed it to the homepage as a blank tile.
-- 1) the square goes with the listing: reward squares, and any manual square with no media of its own;
--    a manual square with its own image/video just loses the link, exactly as before.
-- 2) bk_public_ad_slots never returns a square that has nothing to show, whatever the reason.
-- 3) the one blank square already left behind is removed.

create or replace function public.bk_trg_listing_drop_squares() returns trigger
 language plpgsql security definer set search_path to 'public','extensions' as $$
begin
  delete from ad_slots a
   where a.linked_listing_id = old.id
     and (a.source = 'reward'
          or not (coalesce(a.image_url,'') <> '' or coalesce(a.video_embed_url,'') <> ''
                  or (jsonb_typeof(a.image_urls) = 'array' and jsonb_array_length(a.image_urls) > 0)));
  return old;
end $$;

drop trigger if exists trg_listing_drop_squares on public.listings;
create trigger trg_listing_drop_squares before delete on public.listings
  for each row execute function public.bk_trg_listing_drop_squares();

CREATE OR REPLACE FUNCTION public.bk_public_ad_slots(p_country text DEFAULT 'SY'::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  update listings set is_featured = (featured_from is not null and featured_until is not null and now() between featured_from and featured_until)
   where featured_until is not null and featured_until > now() - interval '1 day'
     and is_featured is distinct from (featured_from is not null and featured_until is not null and now() between featured_from and featured_until);
  return coalesce((select json_agg(x order by x.position) from (
    select a.id, a.position, a.image_url, a.link_url, a.label, a.media_type, a.linked_listing_id, a.image_urls, a.video_embed_url, a.sponsor_name, a.overlay_top, a.overlay_bottom,
           (coalesce(l.is_featured, false) or a.source = 'reward') as featured,
           l.ref as l_ref, l.rooms as l_rooms, l.baths as l_baths, l.area_m2 as l_area, l.property_type as l_type, g.name_ar as l_gov, ar.name_ar as l_area_name,
           coalesce((select json_agg(p.url order by p.sort_order) from listing_photos p where p.listing_id = l.id and p.kind = 'photo'), '[]'::json) as l_photos
      from ad_slots a
      left join listings l on l.id = a.linked_listing_id and l.status = 'live'
      left join governorates g on g.id = l.governorate_id
      left join areas ar on ar.id = l.area_id
     where a.enabled = true and a.country_code = coalesce(p_country,'SY')
       and (a.starts_at is null or a.starts_at <= now()) and (a.expires_at is null or a.expires_at >= now())
       and (a.linked_listing_id is null or l.id is not null)
       -- a square must have something to show: a live listing, or media of its own
       and (l.id is not null or coalesce(a.image_url,'') <> '' or coalesce(a.video_embed_url,'') <> ''
            or (jsonb_typeof(a.image_urls) = 'array' and jsonb_array_length(a.image_urls) > 0))
     order by a.position
     limit bk_ad_max_squares()
  ) x), '[]'::json);
end $function$;

delete from ad_slots
 where enabled and linked_listing_id is null and source = 'reward';

select tgname from pg_trigger where tgrelid = 'public.listings'::regclass and tgname = 'trg_listing_drop_squares';

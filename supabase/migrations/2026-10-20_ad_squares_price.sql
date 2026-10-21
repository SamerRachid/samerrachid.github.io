-- squares on the home page (owner, 2026-10-20): a listing square can show its price (panel switch x:ad_price_enabled)
-- the function is unchanged apart from the four price columns it now returns
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
           l.ref as l_ref, l.price_usd as l_price, l.price_local as l_price_local, l.price_cur as l_price_cur, l.deal as l_deal, l.rooms as l_rooms, l.baths as l_baths, l.area_m2 as l_area, l.property_type as l_type, g.name_ar as l_gov, ar.name_ar as l_area_name,
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

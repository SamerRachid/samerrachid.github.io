-- Balkoun · 2026-09-27 · featured listings (admin-featured or earned with the free-feature reward) show up in the
-- homepage ad squares automatically, as virtual slots ahead of the paid ones — no ad_slots row needed. A listing an
-- admin already linked to a real square is not doubled. Virtual slot ids are negative (-listing id).

create or replace function public.bk_public_ad_slots(p_country text default 'SY') returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
begin
  -- keep the featured flags honest first (same cheap sweep as bk_public_featured_ids)
  update listings set is_featured = (featured_from is not null and featured_until is not null and now() between featured_from and featured_until)
   where featured_until is not null and featured_until > now() - interval '1 day'
     and is_featured is distinct from (featured_from is not null and featured_until is not null and now() between featured_from and featured_until);
  return coalesce((select json_agg(x order by x.position) from (
    select a.id, a.position, a.image_url, a.link_url, a.label, a.media_type, a.linked_listing_id, a.image_urls, a.video_embed_url, a.sponsor_name, a.overlay_top, a.overlay_bottom,
           false as featured,
           l.ref as l_ref, l.rooms as l_rooms, l.baths as l_baths, l.area_m2 as l_area, l.property_type as l_type, g.name_ar as l_gov, ar.name_ar as l_area_name,
           coalesce((select json_agg(p.url order by p.sort_order) from listing_photos p where p.listing_id = l.id and p.kind = 'photo'), '[]'::json) as l_photos
      from ad_slots a
      left join listings l on l.id = a.linked_listing_id and l.status = 'live'
      left join governorates g on g.id = l.governorate_id
      left join areas ar on ar.id = l.area_id
     where a.enabled = true and a.country_code = coalesce(p_country,'SY')
       and (a.starts_at is null or a.starts_at <= now()) and (a.expires_at is null or a.expires_at >= now())
    union all
    select -l.id as id, -1000 + (row_number() over (order by l.featured_from desc nulls last, l.id desc))::int as position,
           null::text, null::text, null::text, 'listing'::text as media_type, l.id as linked_listing_id, null::jsonb, null::text, null::text, null::text, null::text,
           true as featured,
           l.ref, l.rooms, l.baths, l.area_m2, l.property_type, g.name_ar, ar.name_ar,
           coalesce((select json_agg(p.url order by p.sort_order) from listing_photos p where p.listing_id = l.id and p.kind = 'photo'), '[]'::json)
      from listings l
      left join governorates g on g.id = l.governorate_id
      left join areas ar on ar.id = l.area_id
     where l.is_featured = true and l.status = 'live' and l.country_code = coalesce(p_country,'SY')
       and not exists (select 1 from ad_slots a2 where a2.linked_listing_id = l.id and a2.enabled = true and a2.country_code = l.country_code
                         and (a2.starts_at is null or a2.starts_at <= now()) and (a2.expires_at is null or a2.expires_at >= now()))
  ) x), '[]'::json);
end $function$;

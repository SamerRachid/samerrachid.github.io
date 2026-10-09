-- 2026-10-09 — "hide my number" was bypassable (audit findings #1 and #2).
-- 1) listings.contact_phone_private was readable by anon/authenticated through the REST table grant
--    (44 hidden numbers readable with the public key at the time of the audit).
-- 2) bk_by_user() (seller page, anon) and bk_saved_full() (members) returned `l.*`, which includes the private column.
-- Fix: column-level grants on listings (everything except contact_phone_private) and explicit column lists in both
-- functions, with contact_phone nulled when the owner hides it (same rule as v_listings).
-- Side effect: `select *` on listings by anon now fails (column not granted) — the client fallback in index.html
-- (loadListings → DB.from("listings")) was changed to an explicit column list in the same commit.

begin;

revoke select on table public.listings from anon, authenticated;
grant select (
  id, ref, user_id, status, section, deal, property_type, governorate_id, area_id, landmark, lat, lng,
  price_usd, orig_price, closed_reason, price_negotiable, area_m2, rooms, baths, floor, floors_total, year_built,
  tabu, deed_doc_url, condition, power_hours, generator_amps, water_schedule, heating, finish_level, furnished,
  lease_months, advance_months, deposit_usd, bills_included, amenities, description, contact_phone, contact_name,
  accepts_whatsapp, by_owner, views, saves, created_at, updated_at, published_at, expires_at, closed_at, direction,
  rental_period, is_featured, featured_from, featured_until, living_rooms, country_code, reject_reason, rejected_at,
  featured_source, price_local, price_cur
) on table public.listings to anon, authenticated;

CREATE OR REPLACE FUNCTION public.bk_by_user(p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  return coalesce((select json_agg(x) from (
    select l.id, l.ref, l.user_id, l.status, l.section, l.deal, l.property_type, l.governorate_id, l.area_id,
           l.landmark, l.lat, l.lng, l.price_usd, l.orig_price, l.closed_reason, l.price_negotiable, l.area_m2,
           l.rooms, l.baths, l.floor, l.floors_total, l.year_built, l.tabu, l.deed_doc_url, l.condition,
           l.power_hours, l.generator_amps, l.water_schedule, l.heating, l.finish_level, l.furnished,
           l.lease_months, l.advance_months, l.deposit_usd, l.bills_included, l.amenities, l.description,
           case when coalesce(u.hide_phone,false) then null else l.contact_phone end as contact_phone,
           l.contact_name, l.accepts_whatsapp, l.by_owner, l.views, l.saves, l.created_at, l.updated_at,
           l.published_at, l.expires_at, l.closed_at, l.direction, l.rental_period, l.is_featured,
           l.featured_from, l.featured_until, l.living_rooms, l.country_code, l.price_local, l.price_cur,
           g.name_ar as governorate_ar, g.name_en as governorate_en, a.name_ar as area_ar,
           trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as owner_name,
           u.city as owner_city, u.country as owner_country, u.card_logo as owner_card_logo,
           coalesce(u.hide_phone,false) as owner_hide_phone,
           (select coalesce(thumb_url,url) from listing_photos p
             where p.listing_id=l.id order by sort_order limit 1) as cover_url
      from listings l
      join governorates g on g.id=l.governorate_id
      left join areas a on a.id=l.area_id
      left join users u on u.id=l.user_id
     where l.user_id = p_user
       and (l.status='live'
            or (l.status in ('sold','rented') and l.closed_at > now() - interval '7 days'))
     order by l.created_at desc) x), '[]'::json);
end $function$;

CREATE OR REPLACE FUNCTION public.bk_saved_full(p_user uuid, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  return coalesce((select json_agg(x) from (
    select l.id, l.ref, l.user_id, l.status, l.section, l.deal, l.property_type, l.governorate_id, l.area_id,
           l.landmark, l.lat, l.lng, l.price_usd, l.orig_price, l.closed_reason, l.price_negotiable, l.area_m2,
           l.rooms, l.baths, l.floor, l.floors_total, l.year_built, l.tabu, l.deed_doc_url, l.condition,
           l.power_hours, l.generator_amps, l.water_schedule, l.heating, l.finish_level, l.furnished,
           l.lease_months, l.advance_months, l.deposit_usd, l.bills_included, l.amenities, l.description,
           case when coalesce(u.hide_phone,false) then null else l.contact_phone end as contact_phone,
           l.contact_name, l.accepts_whatsapp, l.by_owner, l.views, l.saves, l.created_at, l.updated_at,
           l.published_at, l.expires_at, l.closed_at, l.direction, l.rental_period, l.is_featured,
           l.featured_from, l.featured_until, l.living_rooms, l.country_code, l.price_local, l.price_cur,
           g.name_ar as governorate_ar, g.name_en as governorate_en, a.name_ar as area_ar,
           trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as owner_name,
           u.city as owner_city, u.country as owner_country, u.card_logo as owner_card_logo,
           coalesce(u.hide_phone,false) as owner_hide_phone,
           (select coalesce(thumb_url,url) from listing_photos p where p.listing_id=l.id
             order by sort_order limit 1) as cover_url
      from saved_listings s
      join listings l on l.id = s.listing_id
      join governorates g on g.id = l.governorate_id
      left join areas a on a.id = l.area_id
      left join users u on u.id = l.user_id
     where s.user_id = p_user
     order by s.created_at desc) x), '[]'::json);
end $function$;

commit;

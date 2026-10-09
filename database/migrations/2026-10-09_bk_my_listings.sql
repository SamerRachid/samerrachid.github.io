-- 2026-10-09 — "My ads" (index.html mine()) only ever filtered D.LIST, which is loaded from v_listings
-- restricted to status in ('live','pending') (and sold/rented only within 7 days of closed_at). A member
-- whose listing was rejected, hidden by admin, or sold/rented more than a week ago silently disappeared
-- from their own "My ads" page with no error — there was no RPC that returned a member's own listings
-- regardless of status. This also broke editing and viewing: the edit-form handler and the listing detail
-- page both read their seed row from D.LIST too, so opening a non-live listing of one's own showed a blank
-- edit form or a "not found" page.
--
-- bk_my_listings mirrors v_listings' exact column shape (so the client's existing fromRow() works
-- unchanged) but scopes by the caller's own user_id with no status restriction at all.
--
-- Verified live (throwaway user + listings inside a rolled-back transaction, no real account touched):
-- returned all 4 of live/hidden/rejected/sold(30 days old) rows for one user via their session token.
CREATE OR REPLACE FUNCTION public.bk_my_listings(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_uid uuid;
begin
  v_uid := bk_member_uid(p_token);
  if v_uid is null then return '[]'::json; end if;
  return coalesce((select json_agg(x) from (
    select l.id, l.ref, l.user_id, l.status, l.section, l.deal, l.property_type, l.governorate_id, l.area_id,
           l.landmark, l.lat, l.lng, l.price_usd, l.orig_price, l.closed_reason, l.price_negotiable, l.area_m2,
           l.rooms, l.baths, l.floor, l.floors_total, l.year_built, l.tabu, l.deed_doc_url, l.condition,
           l.power_hours, l.generator_amps, l.water_schedule, l.heating, l.finish_level, l.furnished,
           l.lease_months, l.advance_months, l.deposit_usd, l.bills_included, l.amenities, l.description,
           case when coalesce(u.hide_phone,false) then null else l.contact_phone end as contact_phone,
           l.contact_name, l.accepts_whatsapp, l.by_owner, l.views, l.saves, l.created_at, l.updated_at,
           l.published_at, l.expires_at, l.closed_at, l.direction, l.rental_period, l.is_featured,
           l.featured_from, l.featured_until, l.living_rooms,
           g.name_ar as governorate_ar, g.name_en as governorate_en, a.name_ar as area_ar,
           trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as owner_name,
           u.city as owner_city, u.country as owner_country, u.username as owner_username,
           u.avatar_url as owner_avatar, u.level as owner_level,
           round(l.price_usd::numeric / nullif(l.area_m2,0)::numeric) as price_per_m2,
           (select count(*) from price_history h where h.listing_id=l.id) as price_changes,
           coalesce((select coalesce(p.thumb_url,p.url) from listing_photos p
                      where p.listing_id=l.id and p.kind='photo' order by p.sort_order limit 1),
                    (select p.thumb_url from listing_photos p
                      where p.listing_id=l.id and p.kind='video' and coalesce(p.thumb_url,'')<>'' order by p.sort_order limit 1)) as cover_url,
           (select count(*) from listing_photos p where p.listing_id=l.id and p.kind='photo') as photo_count,
           (select round(avg(r.stars),1) from reviews r where r.target_user=l.user_id) as owner_rating_avg,
           (select count(*) from reviews r where r.target_user=l.user_id) as owner_rating_count,
           u.created_at as owner_created_at, u.card_logo as owner_card_logo,
           coalesce(l.country_code, g.country_code) as country_code,
           (select count(*) from listing_photos p where p.listing_id=l.id and p.kind='video') as video_count,
           u.account_type as owner_type,
           (select ag.id from agencies ag where ag.user_id=l.user_id and ag.status='approved' limit 1) as owner_agency_id,
           (select ag.name from agencies ag where ag.user_id=l.user_id and ag.status='approved' limit 1) as owner_agency_name,
           (select ag.verified from agencies ag where ag.user_id=l.user_id and ag.status='approved' limit 1) as owner_agency_verified,
           (select ag.contact_person from agencies ag where ag.user_id=l.user_id and ag.status='approved' limit 1) as owner_agency_person,
           coalesce(u.hide_phone,false) as owner_hide_phone,
           l.price_local, l.price_cur
      from listings l
      join governorates g on g.id=l.governorate_id
      left join areas a on a.id=l.area_id
      left join users u on u.id=l.user_id
     where l.user_id = v_uid
     order by l.created_at desc) x), '[]'::json);
end $function$;

grant execute on function public.bk_my_listings(text) to anon, authenticated;

-- 2026-10-08 · keep the price exactly as the poster wrote it (amount + currency) next to the USD figure used for sorting.
-- price_usd stays the comparable number; price_local/price_cur show verbatim when the viewer's currency is the poster's.

alter table public.listings add column if not exists price_local numeric, add column if not exists price_cur text;

create or replace view public.v_listings as
 SELECT l.id,
    l.ref,
    l.user_id,
    l.status,
    l.section,
    l.deal,
    l.property_type,
    l.governorate_id,
    l.area_id,
    l.landmark,
    l.lat,
    l.lng,
    l.price_usd,
    l.orig_price,
    l.closed_reason,
    l.price_negotiable,
    l.area_m2,
    l.rooms,
    l.baths,
    l.floor,
    l.floors_total,
    l.year_built,
    l.tabu,
    l.deed_doc_url,
    l.condition,
    l.power_hours,
    l.generator_amps,
    l.water_schedule,
    l.heating,
    l.finish_level,
    l.furnished,
    l.lease_months,
    l.advance_months,
    l.deposit_usd,
    l.bills_included,
    l.amenities,
    l.description,
        CASE
            WHEN COALESCE(u.hide_phone, false) THEN NULL::text
            ELSE l.contact_phone
        END AS contact_phone,
    l.contact_name,
    l.accepts_whatsapp,
    l.by_owner,
    l.views,
    l.saves,
    l.created_at,
    l.updated_at,
    l.published_at,
    l.expires_at,
    l.closed_at,
    l.direction,
    l.rental_period,
    l.is_featured,
    l.featured_from,
    l.featured_until,
    l.living_rooms,
    g.name_ar AS governorate_ar,
    g.name_en AS governorate_en,
    a.name_ar AS area_ar,
    TRIM(BOTH FROM (COALESCE(u.name, ''::text) || ' '::text) || COALESCE(u.family_name, ''::text)) AS owner_name,
    u.city AS owner_city,
    u.country AS owner_country,
    u.username AS owner_username,
    u.avatar_url AS owner_avatar,
    u.level AS owner_level,
    round(l.price_usd::numeric / NULLIF(l.area_m2, 0)::numeric) AS price_per_m2,
    ( SELECT count(*) AS count
           FROM price_history h
          WHERE h.listing_id = l.id) AS price_changes,
    COALESCE(( SELECT COALESCE(p.thumb_url, p.url) AS "coalesce"
           FROM listing_photos p
          WHERE p.listing_id = l.id AND p.kind = 'photo'::text
          ORDER BY p.sort_order
         LIMIT 1), ( SELECT p.thumb_url
           FROM listing_photos p
          WHERE p.listing_id = l.id AND p.kind = 'video'::text AND COALESCE(p.thumb_url, ''::text) <> ''::text
          ORDER BY p.sort_order
         LIMIT 1)) AS cover_url,
    ( SELECT count(*) AS count
           FROM listing_photos p
          WHERE p.listing_id = l.id AND p.kind = 'photo'::text) AS photo_count,
    ( SELECT round(avg(r.stars), 1) AS round
           FROM reviews r
          WHERE r.target_user = l.user_id) AS owner_rating_avg,
    ( SELECT count(*) AS count
           FROM reviews r
          WHERE r.target_user = l.user_id) AS owner_rating_count,
    u.created_at AS owner_created_at,
    u.card_logo AS owner_card_logo,
    COALESCE(l.country_code, g.country_code) AS country_code,
    ( SELECT count(*) AS count
           FROM listing_photos p
          WHERE p.listing_id = l.id AND p.kind = 'video'::text) AS video_count,
    u.account_type AS owner_type,
    ( SELECT ag.id
           FROM agencies ag
          WHERE ag.user_id = l.user_id AND ag.status = 'approved'::text
         LIMIT 1) AS owner_agency_id,
    ( SELECT ag.name
           FROM agencies ag
          WHERE ag.user_id = l.user_id AND ag.status = 'approved'::text
         LIMIT 1) AS owner_agency_name,
    ( SELECT ag.verified
           FROM agencies ag
          WHERE ag.user_id = l.user_id AND ag.status = 'approved'::text
         LIMIT 1) AS owner_agency_verified,
    ( SELECT ag.contact_person
           FROM agencies ag
          WHERE ag.user_id = l.user_id AND ag.status = 'approved'::text
         LIMIT 1) AS owner_agency_person,
    COALESCE(u.hide_phone, false) AS owner_hide_phone,
    l.price_local,
    l.price_cur
   FROM listings l
     JOIN governorates g ON g.id = l.governorate_id
     LEFT JOIN areas a ON a.id = l.area_id
     LEFT JOIN users u ON u.id = l.user_id
  WHERE (l.status = ANY (ARRAY['live'::text, 'pending'::text])) OR (l.status = ANY (ARRAY['sold'::text, 'rented'::text])) AND l.closed_at > (now() - '7 days'::interval);

do $do$
declare src text;
begin
  src := pg_get_functiondef(('public.' || 'bk_intake_publish')::regproc);
  if position($q$      price_usd, price_negotiable, area_m2,$q$ in src) = 0 then raise exception 'bk_intake_publish: pattern not found: %', $q$      price_usd, price_negotiable, area_$q$; end if;
  src := replace(src, $q$      price_usd, price_negotiable, area_m2,$q$, $q$      price_usd, price_local, price_cur, price_negotiable, area_m2,$q$);
  if position($q$      usd, bk_intake_bool(f->>'negotiable', true), m2,$q$ in src) = 0 then raise exception 'bk_intake_publish: pattern not found: %', $q$      usd, bk_intake_bool(f->>'negotiabl$q$; end if;
  src := replace(src, $q$      usd, bk_intake_bool(f->>'negotiable', true), m2,$q$, $q$      usd, case when cur <> 'USD' and price > 0 then price else null end, case when cur <> 'USD' and price > 0 then cur else null end, bk_intake_bool(f->>'negotiable', true), m2,$q$);
  execute src;
  src := pg_get_functiondef(('public.' || 'bk_intake_patch_listing')::regproc);
  if position($q$price_usd = v_usd,$q$ in src) = 0 then raise exception 'bk_intake_patch_listing: pattern not found: %', $q$price_usd = v_usd,$q$; end if;
  src := replace(src, $q$price_usd = v_usd,$q$, $q$price_usd = v_usd, price_local = case when cur <> 'USD' and v_price > 0 then v_price else null end, price_cur = case when cur <> 'USD' and v_price > 0 then cur else null end,$q$);
  execute src;
  src := pg_get_functiondef(('public.' || 'bk_edit')::regproc);
  if position($q$    price_usd   = v_new_price,$q$ in src) = 0 then raise exception 'bk_edit: pattern not found: %', $q$    price_usd   = v_new_price,$q$; end if;
  src := replace(src, $q$    price_usd   = v_new_price,$q$, $q$    price_usd   = v_new_price,
    price_local = case when p_patch ? 'price_local' then nullif(p_patch->>'price_local','')::numeric else price_local end,
    price_cur   = case when p_patch ? 'price_cur' then nullif(p_patch->>'price_cur','') else price_cur end,$q$);
  execute src;
  src := pg_get_functiondef(('public.' || 'bk_admin_edit_listing')::regproc);
  if position($q$price_usd = v_new_price, area_m2$q$ in src) = 0 then raise exception 'bk_admin_edit_listing: pattern not found: %', $q$price_usd = v_new_price, area_m2$q$; end if;
  src := replace(src, $q$price_usd = v_new_price, area_m2$q$, $q$price_usd = v_new_price, price_local = case when p_patch ? 'price_local' then nullif(p_patch->>'price_local','')::numeric else price_local end, price_cur = case when p_patch ? 'price_cur' then nullif(p_patch->>'price_cur','') else price_cur end, area_m2$q$);
  execute src;
end $do$;

select (select count(*) from pg_proc p where p.proname in ('bk_edit','bk_admin_edit_listing','bk_intake_publish','bk_intake_patch_listing') and pg_get_functiondef(p.oid) like '%price_local%') as functions_updated, (select count(*) from information_schema.columns where table_name='v_listings' and column_name='price_local') as view_has_col;

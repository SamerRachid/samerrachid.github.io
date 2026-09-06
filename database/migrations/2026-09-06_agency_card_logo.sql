-- 2026-09-06 · agency logo on listing cards: a per-account switch (admin only). The card shows the
-- account's avatar as a logo next to its name when card_logo is on.
alter table public.users add column if not exists card_logo boolean not null default false;

create or replace view public.v_listings as
 SELECT l.id, l.ref, l.user_id, l.status, l.section, l.deal, l.property_type, l.governorate_id, l.area_id, l.landmark,
    l.lat, l.lng, l.price_usd, l.orig_price, l.closed_reason, l.price_negotiable, l.area_m2, l.rooms, l.baths, l.floor,
    l.floors_total, l.year_built, l.tabu, l.deed_doc_url, l.condition, l.power_hours, l.generator_amps, l.water_schedule,
    l.heating, l.finish_level, l.furnished, l.lease_months, l.advance_months, l.deposit_usd, l.bills_included, l.amenities,
    l.description, l.contact_phone, l.contact_name, l.accepts_whatsapp, l.by_owner, l.views, l.saves, l.created_at,
    l.updated_at, l.published_at, l.expires_at, l.closed_at, l.direction, l.rental_period, l.is_featured, l.featured_from,
    l.featured_until, l.living_rooms,
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
    ( SELECT count(*) AS count FROM price_history h WHERE h.listing_id = l.id) AS price_changes,
    ( SELECT COALESCE(p.thumb_url, p.url) AS "coalesce" FROM listing_photos p WHERE p.listing_id = l.id ORDER BY p.sort_order LIMIT 1) AS cover_url,
    ( SELECT count(*) AS count FROM listing_photos p WHERE p.listing_id = l.id) AS photo_count,
    ( SELECT round(avg(r.stars), 1) AS round FROM reviews r WHERE r.target_user = l.user_id) AS owner_rating_avg,
    ( SELECT count(*) AS count FROM reviews r WHERE r.target_user = l.user_id) AS owner_rating_count,
    u.created_at AS owner_created_at,
    u.card_logo AS owner_card_logo
   FROM listings l
     JOIN governorates g ON g.id = l.governorate_id
     LEFT JOIN areas a ON a.id = l.area_id
     LEFT JOIN users u ON u.id = l.user_id
  WHERE (l.status = ANY (ARRAY['live'::text, 'pending'::text])) OR (l.status = ANY (ARRAY['sold'::text, 'rented'::text])) AND l.closed_at > (now() - '7 days'::interval);

create or replace function public.bk_admin_set_card_logo(p_token text, p_user uuid, p_on boolean)
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update users set card_logo = p_on where id = p_user and role <> 'admin';
  return json_build_object('ok', true);
end $function$;

create or replace function public.bk_admin_card_logos(p_token text)
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  return coalesce((select json_agg(id) from users where card_logo), '[]'::json);
end $function$;

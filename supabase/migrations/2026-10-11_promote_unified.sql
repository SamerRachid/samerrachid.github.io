-- 2026-10-11: one «ترويج» (promote) action per listing, two independent places.
--   • top of the search results  = listings.featured_from / featured_until (is_featured), exactly as before
--   • a square on the home page  = a linked ad_slots row for that listing
-- Until today a featured listing was ALSO pushed into the home squares automatically (a UNION inside
-- bk_public_ad_slots), so the two could never be chosen separately, and the admin had two panels ("featured" and
-- the ad-squares studio) that overlapped. Now the squares come only from ad_slots; a listing is promoted from one
-- dialog (admin tab «الترويج» or the listing drawer) that ticks either place or both; the member's free reward stays
-- top-of-search only. The listings featured right now get a linked square so nothing disappears from the home page.
--
-- Squares are capped: site_content.extras.ad_max_squares (global row, default 15 — the owner will drop it to 6
-- later). The cap is enforced in bk_admin_save_ad (studio) and so in bk_admin_promote, and bk_public_ad_slots
-- never returns more than that.
--
--   bk_ad_max_squares()                          cap
--   bk_ad_squares_used(cc, except)               enabled, unexpired squares in a country
--   bk_admin_save_ad(...)                        + cap check when a square is created or switched on
--   bk_public_ad_slots(cc)                       no featured UNION; `featured` = linked listing is top-featured; limit cap
--   bk_admin_promo_info(token, listing)          state of one listing: top, home square, member credit, squares used
--   bk_admin_promote(token, listing, top, home, from, days, client, use_credit)
--   bk_admin_promote_end(token, listing, top, home)
--   bk_admin_list_promos(token, country)         every promoted listing (either place) for the admin tab

create or replace function public.bk_ad_max_squares() returns integer
language sql stable security definer set search_path = public as $$
  select greatest(1, coalesce(nullif(extras->>'ad_max_squares','')::int, 15)) from public.site_content where id = 1
$$;

create or replace function public.bk_ad_squares_used(p_cc text, p_except bigint default null) returns integer
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.ad_slots
   where country_code = coalesce(p_cc,'SY') and enabled = true
     and (expires_at is null or expires_at >= now())
     and (p_except is null or id <> p_except)
$$;

CREATE OR REPLACE FUNCTION public.bk_admin_save_ad(p_token text, p_id bigint, p_position integer, p_image_url text, p_link_url text, p_label text, p_enabled boolean, p_media_type text, p_linked_listing_id bigint, p_image_urls jsonb, p_video_embed_url text, p_sponsor_name text DEFAULT NULL::text, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_overlay_top text DEFAULT NULL::text, p_overlay_bottom text DEFAULT NULL::text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; v_id bigint; v_pos int; v_code text; v_active public.engagements; v_title text; v_lref text; v_c text := coalesce(p_country,'SY'); v_was_on boolean := false;
begin
  uid := bk_admin_uid(p_token);
  if p_id is not null then select enabled, coalesce(p_country, country_code) into v_was_on, v_c from ad_slots where id = p_id; end if;
  -- the cap: a square that is new, or switched on just now, needs a free place (editing one already on never fails)
  if coalesce(p_enabled,true) and not coalesce(v_was_on,false)
     and bk_ad_squares_used(v_c, p_id) >= bk_ad_max_squares() then
    raise exception 'max_squares';
  end if;
  if p_id is null then
    select coalesce(max(position),0)+1 into v_pos from ad_slots where country_code=v_c;
    insert into ad_slots (position, image_url, link_url, label, enabled, media_type, linked_listing_id, image_urls, video_embed_url, sponsor_name, starts_at, expires_at, overlay_top, overlay_bottom, country_code)
      values (v_pos, p_image_url, p_link_url, p_label, coalesce(p_enabled,true), coalesce(p_media_type,'image'), p_linked_listing_id,
        coalesce(p_image_urls,'[]'::jsonb), p_video_embed_url, p_sponsor_name, p_starts_at, p_expires_at, p_overlay_top, p_overlay_bottom, v_c)
      returning id into v_id;
  else
    update ad_slots set image_url=p_image_url, link_url=p_link_url, label=p_label, enabled=coalesce(p_enabled,true), media_type=coalesce(p_media_type,'image'),
      linked_listing_id=p_linked_listing_id, image_urls=coalesce(p_image_urls,'[]'::jsonb), video_embed_url=p_video_embed_url, sponsor_name=p_sponsor_name,
      starts_at=p_starts_at, expires_at=p_expires_at, overlay_top=p_overlay_top, overlay_bottom=p_overlay_bottom, country_code=coalesce(p_country,country_code) where id=p_id;
    v_id := p_id;
  end if;
  select ref into v_lref from listings where id=p_linked_listing_id;
  v_title := coalesce(nullif(p_label,''), nullif(p_sponsor_name,''), v_lref, 'مربع #'||v_id);
  select * into v_active from public.engagements where kind='ad' and ref_id=v_id and status='active' order by created_at desc limit 1;
  if coalesce(p_enabled,true) then
    if v_active.id is null then
      v_active := public.bk_engage('ad', v_id, v_lref, v_title, p_sponsor_name, null, p_starts_at, p_expires_at, null, uid);
    else
      update public.engagements set title=v_title, client_name=coalesce(nullif(p_sponsor_name,''),client_name), starts_at=coalesce(p_starts_at,starts_at), ends_at=p_expires_at, ref_text=coalesce(v_lref,ref_text)
       where id=v_active.id;
    end if;
    v_code := v_active.code;
  else
    perform public.bk_engage_end('ad', v_id, null, 'ended');
  end if;
  update engagements set country_code=(select country_code from ad_slots where id=v_id) where kind='ad' and ref_id=v_id;
  return json_build_object('ok', true, 'id', v_id, 'code', v_code);
end $function$;

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
  -- squares come from ad_slots only; a square linked to a listing that is no longer live is skipped (it would be empty)
  return coalesce((select json_agg(x order by x.position) from (
    select a.id, a.position, a.image_url, a.link_url, a.label, a.media_type, a.linked_listing_id, a.image_urls, a.video_embed_url, a.sponsor_name, a.overlay_top, a.overlay_bottom,
           coalesce(l.is_featured, false) as featured,
           l.ref as l_ref, l.rooms as l_rooms, l.baths as l_baths, l.area_m2 as l_area, l.property_type as l_type, g.name_ar as l_gov, ar.name_ar as l_area_name,
           coalesce((select json_agg(p.url order by p.sort_order) from listing_photos p where p.listing_id = l.id and p.kind = 'photo'), '[]'::json) as l_photos
      from ad_slots a
      left join listings l on l.id = a.linked_listing_id and l.status = 'live'
      left join governorates g on g.id = l.governorate_id
      left join areas ar on ar.id = l.area_id
     where a.enabled = true and a.country_code = coalesce(p_country,'SY')
       and (a.starts_at is null or a.starts_at <= now()) and (a.expires_at is null or a.expires_at >= now())
       and (a.linked_listing_id is null or l.id is not null)
     order by a.position
     limit bk_ad_max_squares()
  ) x), '[]'::json);
end $function$;

create or replace function public.bk_admin_promo_info(p_token text, p_listing bigint)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare uid uuid; l listings; s ad_slots; u users; b json;
begin
  uid := bk_admin_uid(p_token);
  select * into l from listings where id = p_listing;
  if l.id is null then return json_build_object('error','nolisting'); end if;
  perform bk_admin_guard(uid, l.country_code);
  perform bk_recompute_featured(l.id);
  select * into l from listings where id = p_listing;
  select * into s from ad_slots where linked_listing_id = l.id order by enabled desc, expires_at desc nulls first, id desc limit 1;
  select * into u from users where id = l.user_id;
  if u.id is not null then b := bk_reward_balance(u.id); end if;
  return json_build_object(
    'id', l.id, 'ref', l.ref, 'status', l.status, 'country_code', l.country_code, 'user_id', l.user_id,
    'poster_name', trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),
    'top', case when l.featured_until is null then null else json_build_object(
        'from', l.featured_from, 'until', l.featured_until, 'source', l.featured_source,
        'active', (l.featured_from <= now() and l.featured_until >= now()),
        'code', (select code from engagements where kind='featured' and ref_id=l.id and status='active' order by created_at desc limit 1)) end,
    'home', case when s.id is null then null else json_build_object(
        'slot_id', s.id, 'enabled', s.enabled, 'from', s.starts_at, 'until', s.expires_at, 'sponsor_name', s.sponsor_name,
        'active', (s.enabled and (s.starts_at is null or s.starts_at <= now()) and (s.expires_at is null or s.expires_at >= now())),
        'code', (select code from engagements where kind='ad' and ref_id=s.id and status='active' order by created_at desc limit 1)) end,
    'member', case when u.id is null then null else json_build_object(
        'credits', (b->>'credits')::int, 'hours', (b->>'hours')::int,
        'active_listing_id', b->'active_listing_id', 'active_until', b->'active_until') end,
    'squares', json_build_object('used', bk_ad_squares_used(l.country_code, null), 'max', bk_ad_max_squares()));
end $function$;

-- p_use_credit: spend ONE of the member's free-feature credits on this listing instead of an admin feature — same
-- effect as the member pressing «استخدم التمييز» himself (reward hours, starts now, featured_source = 'reward',
-- a 'used' reward event noted as done by the admin), so he sees it spent and cannot ask for it again.
create or replace function public.bk_admin_promote(p_token text, p_listing bigint, p_top boolean, p_home boolean, p_from timestamptz, p_days integer, p_client text default null, p_use_credit boolean default false)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare uid uuid; l listings; u users; s ad_slots; b json; hrs int; v_from timestamptz; v_until timestamptz; r engagements; rr json;
        v_name text; v_client text; v_phone text; v_code_top text; v_code_home text;
begin
  uid := bk_admin_uid(p_token);
  select * into l from listings where id = p_listing;
  if l.id is null then return json_build_object('error','nolisting'); end if;
  perform bk_admin_guard(uid, l.country_code);
  if not coalesce(p_top,false) and not coalesce(p_home,false) then return json_build_object('error','nothing'); end if;
  if l.status <> 'live' then return json_build_object('error','notlive'); end if;
  select * into u from users where id = l.user_id;
  v_name := nullif(trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')), '');
  v_client := coalesce(nullif(trim(coalesce(p_client,'')),''), v_name);
  v_phone := coalesce(l.contact_phone, u.phone);
  v_from := coalesce(p_from, now());

  if coalesce(p_top,false) then
    if coalesce(p_use_credit,false) then
      if u.id is null then return json_build_object('error','nouser'); end if;
      b := bk_reward_balance(u.id);
      if (b->>'credits')::int < 1 then return json_build_object('error','nocredit'); end if;
      if b->>'active_listing_id' is not null then return json_build_object('error','active', 'until', b->>'active_until'); end if;
      hrs := (b->>'hours')::int; v_until := now() + make_interval(hours => hrs);
      update listings set featured_from = now(), featured_until = v_until, is_featured = true, featured_source = 'reward' where id = l.id;
      insert into reward_events (user_id, kind, listing_id, delta, note, created_by) values (u.id, 'used', l.id, -1, hrs || 'h feature · admin', uid);
      perform bk_engage_end('featured', l.id, null, 'ended');
    else
      if p_days is null or p_days < 1 then return json_build_object('error','baddays'); end if;
      v_until := v_from + make_interval(days => p_days);
      update listings set featured_from = v_from, featured_until = v_until, featured_source = 'admin' where id = l.id;
      perform bk_recompute_featured(l.id);
      r := bk_engage('featured', l.id, l.ref, l.ref, v_client, v_phone, v_from, v_until, null, uid);
      v_code_top := r.code;
    end if;
  end if;

  if coalesce(p_home,false) then
    if p_days is null or p_days < 1 then return json_build_object('error','baddays'); end if;
    v_until := v_from + make_interval(days => p_days);
    -- reuse the listing's square if it has one (even an expired one), else a new one — bk_admin_save_ad applies the cap
    select * into s from ad_slots where linked_listing_id = l.id order by enabled desc, id desc limit 1;
    rr := bk_admin_save_ad(p_token, s.id, null, null, null, coalesce(s.label,''), true, 'image', l.id, coalesce(s.image_urls,'[]'::jsonb), null,
                           nullif(trim(coalesce(p_client,'')),''), v_from, v_until, s.overlay_top, s.overlay_bottom, l.country_code);
    v_code_home := rr->>'code';
  end if;

  return (json_build_object('ok', true, 'code_top', v_code_top, 'code_home', v_code_home)::jsonb || bk_admin_promo_info(p_token, l.id)::jsonb)::json;
end $function$;

create or replace function public.bk_admin_promote_end(p_token text, p_listing bigint, p_top boolean, p_home boolean)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare uid uuid; l listings; s record;
begin
  uid := bk_admin_uid(p_token);
  select * into l from listings where id = p_listing;
  if l.id is null then return json_build_object('error','nolisting'); end if;
  perform bk_admin_guard(uid, l.country_code);
  if coalesce(p_top,false) then
    update listings set featured_from = null, featured_until = null, is_featured = false where id = l.id;
    perform bk_engage_end('featured', l.id, null, 'cancelled');
  end if;
  if coalesce(p_home,false) then
    for s in select id from ad_slots where linked_listing_id = l.id loop
      perform bk_engage_end('ad', s.id, null, 'cancelled');
      delete from ad_slots where id = s.id;
    end loop;
  end if;
  return bk_admin_promo_info(p_token, l.id);
end $function$;

create or replace function public.bk_admin_list_promos(p_token text, p_country text default null)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare uid uuid; sc text; al text[]; v_cc text;
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  v_cc := coalesce(nullif(p_country,'ALL'), 'SY');
  update listings set is_featured = (featured_from is not null and featured_until is not null and now() between featured_from and featured_until)
   where featured_until is not null and featured_until > now() - interval '1 day'
     and is_featured is distinct from (featured_from is not null and featured_until is not null and now() between featured_from and featured_until);
  return json_build_object(
    'rows', coalesce((select json_agg(x order by x.sort_until desc nulls last, x.id desc) from (
      select l.id, l.ref, l.status, l.country_code, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as poster_name,
             l.featured_from as top_from, l.featured_until as top_until, l.featured_source as top_source,
             (l.featured_until is not null and l.featured_until > now() - interval '1 day') as has_top,
             l.is_featured as top_active,
             s.id as slot_id, s.enabled as home_enabled, s.starts_at as home_from, s.expires_at as home_until, s.sponsor_name,
             (s.id is not null and s.enabled and (s.starts_at is null or s.starts_at <= now()) and (s.expires_at is null or s.expires_at >= now())) as home_active,
             greatest(case when l.featured_until > now() - interval '1 day' then l.featured_until end, s.expires_at) as sort_until
        from listings l
        left join users u on u.id = l.user_id
        left join lateral (select * from ad_slots a where a.linked_listing_id = l.id and (a.expires_at is null or a.expires_at > now() - interval '1 day')
                             order by a.enabled desc, a.id desc limit 1) s on true
       where bk_scope_ok(l.country_code, sc, al)
         and ((l.featured_until is not null and l.featured_until > now() - interval '1 day') or s.id is not null)) x), '[]'::json),
    'squares', json_build_object('used', bk_ad_squares_used(v_cc, null), 'max', bk_ad_max_squares(),
        'custom', (select count(*) from ad_slots where linked_listing_id is null and enabled = true and country_code = v_cc and (expires_at is null or expires_at >= now()))));
end $function$;

-- keep the home page as it is today: every listing featured right now by the admin gets its own square
insert into public.ad_slots (position, enabled, media_type, linked_listing_id, image_urls, starts_at, expires_at, country_code)
select (select coalesce(max(position),0) from public.ad_slots a2 where a2.country_code = l.country_code)
         + row_number() over (partition by l.country_code order by l.featured_from, l.id),
       true, 'image', l.id, '[]'::jsonb, l.featured_from, l.featured_until, l.country_code
  from public.listings l
 where l.is_featured = true and l.status = 'live' and coalesce(l.featured_source,'admin') = 'admin'
   and not exists (select 1 from public.ad_slots a where a.linked_listing_id = l.id);

update public.site_content set extras = coalesce(extras,'{}'::jsonb) || '{"ad_max_squares": 15}'::jsonb
 where id = 1 and not (coalesce(extras,'{}'::jsonb) ? 'ad_max_squares');

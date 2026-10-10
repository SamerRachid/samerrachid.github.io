-- 2026-10-11 (same day, owner's correction): the member's free-feature reward is a SQUARE ON THE HOME PAGE, not the top
-- of the search results. Spending a credit — by the member himself (bk_use_feature_credit) or by the admin on his behalf
-- (bk_admin_promote p_use_credit) — now creates / re-arms the listing's linked home square for the reward hours, marked
-- ad_slots.source = 'reward'. The listing's featured_* columns (top of search) are no longer touched by the reward.
-- The square cap applies: when the strip is full the credit stays unspent and the caller gets 'full' / 'max_squares'.

alter table public.ad_slots add column if not exists source text;   -- 'admin' (promote dialog) | 'reward' (member credit) | null (studio)

-- the listing's home square for a reward: re-arm its old square or insert a new one; null when the strip is full
create or replace function public.bk_reward_square(p_listing bigint, p_hours integer) returns bigint
language plpgsql security definer set search_path to 'public','extensions' as $function$
declare l listings; s ad_slots; v_id bigint; v_pos int; v_until timestamptz := now() + make_interval(hours => greatest(1, coalesce(p_hours, 24)));
begin
  select * into l from listings where id = p_listing;
  if l.id is null then return null; end if;
  select * into s from ad_slots where linked_listing_id = l.id order by enabled desc, id desc limit 1;
  if s.id is not null then
    if bk_ad_squares_used(l.country_code, s.id) >= bk_ad_max_squares() then return null; end if;
    update ad_slots set enabled = true, starts_at = now(), expires_at = v_until, source = 'reward', sponsor_name = null where id = s.id;
    return s.id;
  end if;
  if bk_ad_squares_used(l.country_code, null) >= bk_ad_max_squares() then return null; end if;
  select coalesce(max(position),0)+1 into v_pos from ad_slots where country_code = l.country_code;
  insert into ad_slots (position, enabled, media_type, linked_listing_id, image_urls, starts_at, expires_at, country_code, source)
    values (v_pos, true, 'image', l.id, '[]'::jsonb, now(), v_until, l.country_code, 'reward') returning id into v_id;
  return v_id;
end $function$;
revoke all on function public.bk_reward_square(bigint, integer) from public;

CREATE OR REPLACE FUNCTION public.bk_reward_balance(p_uid uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare cfg jsonb := bk_reward_cfg(); pts int; cr int; ev int; act record;
begin
  select coalesce(sum(case kind when 'point' then 1 when 'point_revoked' then -1 else 0 end), 0),
         coalesce(sum(case when kind in ('earned','welcome','used','granted','revoked') then delta else 0 end), 0)
    into pts, cr from reward_events where user_id = p_uid;
  ev := greatest(1, coalesce((cfg->>'reward_every')::int, 10));
  -- the reward now lives in the home squares: the member's listing whose reward square is still running
  select a.linked_listing_id as id, a.expires_at as featured_until into act
    from ad_slots a join listings l on l.id = a.linked_listing_id
   where l.user_id = p_uid and a.source = 'reward' and a.enabled = true and a.expires_at > now()
   order by a.expires_at desc limit 1;
  return json_build_object('on', coalesce(cfg->>'reward_on', 'true') <> 'false', 'earning', bk_reward_earning(cfg, p_uid), 'until', bk_reward_window_end(cfg, p_uid),
    'days', coalesce(nullif(cfg->>'reward_days', '')::int, 60),
    'every', ev, 'hours', greatest(1, coalesce((cfg->>'reward_hours')::int, 24)),
    'welcome_on', coalesce(cfg->>'reward_welcome_on', 'true') <> 'false', 'points', greatest(pts, 0), 'credits', greatest(cr, 0),
    'next_in', case when pts <= 0 then ev else ev - (pts % ev) end,
    'active_listing_id', act.id, 'active_until', act.featured_until);
end $function$;

CREATE OR REPLACE FUNCTION public.bk_use_feature_credit(p_token text, p_listing bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; b json; l listings; hrs int; sid bigint;
begin
  uid := bk_member_uid(p_token); if uid is null then return json_build_object('error', 'unauthorised'); end if;
  b := bk_reward_balance(uid);
  if (b->>'credits')::int < 1 then return json_build_object('error', 'nocredit'); end if;
  if b->>'active_listing_id' is not null then return json_build_object('error', 'active', 'until', b->>'active_until'); end if;
  select * into l from listings where id = p_listing and user_id = uid;
  if l.id is null then return json_build_object('error', 'notyours'); end if;
  if l.status <> 'live' then return json_build_object('error', 'notlive'); end if;
  if exists (select 1 from ad_slots a where a.linked_listing_id = l.id and a.enabled and (a.starts_at is null or a.starts_at <= now()) and (a.expires_at is null or a.expires_at > now()))
    then return json_build_object('error', 'already'); end if;
  hrs := (b->>'hours')::int;
  sid := bk_reward_square(l.id, hrs);
  if sid is null then return json_build_object('error', 'full'); end if;
  insert into reward_events (user_id, kind, listing_id, delta, note) values (uid, 'used', l.id, -1, hrs || 'h home square');
  return json_build_object('ok', true, 'until', (select expires_at from ad_slots where id = sid));
end $function$;

CREATE OR REPLACE FUNCTION public.bk_admin_rewards(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[]; cfg jsonb := bk_reward_cfg();
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return json_build_object(
    'cfg', cfg,
    'balances', coalesce((select json_agg(x order by x.credits desc, x.points desc) from (
        select u.id as user_id, trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')) as name, u.member_no, u.phone, u.country,
               (select name from agencies a where a.user_id = u.id and a.status = 'approved' limit 1) as agency,
               coalesce(sum(case e.kind when 'point' then 1 when 'point_revoked' then -1 else 0 end), 0)::int as points,
               coalesce(sum(case when e.kind in ('earned','welcome','used','granted','revoked') then e.delta else 0 end), 0)::int as credits,
               (select a.expires_at from ad_slots a join listings l on l.id = a.linked_listing_id where l.user_id = u.id and a.source = 'reward' and a.enabled and a.expires_at > now() order by a.expires_at desc limit 1) as active_until,
               bk_reward_window_end(cfg, u.id) as window_end
          from users u join reward_events e on e.user_id = u.id
         where bk_scope_ok(u.country, sc, al) group by u.id) x), '[]'::json),
    'events', coalesce((select json_agg(x) from (
        select e.id, e.kind, e.delta, e.note, e.created_at, e.listing_id, trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')) as name, u.member_no
          from reward_events e join users u on u.id = e.user_id where bk_scope_ok(u.country, sc, al) order by e.created_at desc limit 60) x), '[]'::json));
end $function$;

-- a reward square keeps the gold frame + star the members' free feature always had
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
        'slot_id', s.id, 'enabled', s.enabled, 'from', s.starts_at, 'until', s.expires_at, 'sponsor_name', s.sponsor_name, 'source', s.source,
        'active', (s.enabled and (s.starts_at is null or s.starts_at <= now()) and (s.expires_at is null or s.expires_at >= now())),
        'code', (select code from engagements where kind='ad' and ref_id=s.id and status='active' order by created_at desc limit 1)) end,
    'member', case when u.id is null then null else json_build_object(
        'credits', (b->>'credits')::int, 'hours', (b->>'hours')::int,
        'active_listing_id', b->'active_listing_id', 'active_until', b->'active_until') end,
    'squares', json_build_object('used', bk_ad_squares_used(l.country_code, null), 'max', bk_ad_max_squares()));
end $function$;

-- p_use_credit: spend ONE of the member's free credits = his listing in a home square for the reward hours, starting now
-- (exactly what he gets when he presses «ميّز على الرئيسية» himself). p_top / p_home stay admin placements.
create or replace function public.bk_admin_promote(p_token text, p_listing bigint, p_top boolean, p_home boolean, p_from timestamptz, p_days integer, p_client text default null, p_use_credit boolean default false)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare uid uuid; l listings; u users; s ad_slots; b json; hrs int; sid bigint; v_from timestamptz; v_until timestamptz; r engagements; rr json;
        v_name text; v_client text; v_phone text; v_code_top text; v_code_home text;
begin
  uid := bk_admin_uid(p_token);
  select * into l from listings where id = p_listing;
  if l.id is null then return json_build_object('error','nolisting'); end if;
  perform bk_admin_guard(uid, l.country_code);
  if not coalesce(p_top,false) and not coalesce(p_home,false) and not coalesce(p_use_credit,false) then return json_build_object('error','nothing'); end if;
  if l.status <> 'live' then return json_build_object('error','notlive'); end if;
  select * into u from users where id = l.user_id;
  v_name := nullif(trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')), '');
  v_client := coalesce(nullif(trim(coalesce(p_client,'')),''), v_name);
  v_phone := coalesce(l.contact_phone, u.phone);
  v_from := coalesce(p_from, now());

  if coalesce(p_use_credit,false) then
    if u.id is null then return json_build_object('error','nouser'); end if;
    b := bk_reward_balance(u.id);
    if (b->>'credits')::int < 1 then return json_build_object('error','nocredit'); end if;
    if b->>'active_listing_id' is not null then return json_build_object('error','active', 'until', b->>'active_until'); end if;
    hrs := (b->>'hours')::int;
    sid := bk_reward_square(l.id, hrs);
    if sid is null then return json_build_object('error','max_squares'); end if;
    insert into reward_events (user_id, kind, listing_id, delta, note, created_by) values (u.id, 'used', l.id, -1, hrs || 'h home square · admin', uid);
  elsif coalesce(p_home,false) then
    if p_days is null or p_days < 1 then return json_build_object('error','baddays'); end if;
    v_until := v_from + make_interval(days => p_days);
    select * into s from ad_slots where linked_listing_id = l.id order by enabled desc, id desc limit 1;
    rr := bk_admin_save_ad(p_token, s.id, null, null, null, coalesce(s.label,''), true, 'image', l.id, coalesce(s.image_urls,'[]'::jsonb), null,
                           nullif(trim(coalesce(p_client,'')),''), v_from, v_until, s.overlay_top, s.overlay_bottom, l.country_code);
    v_code_home := rr->>'code';
    update ad_slots set source = 'admin' where id = (rr->>'id')::bigint;
  end if;

  if coalesce(p_top,false) then
    if p_days is null or p_days < 1 then return json_build_object('error','baddays'); end if;
    v_until := v_from + make_interval(days => p_days);
    update listings set featured_from = v_from, featured_until = v_until, featured_source = 'admin' where id = l.id;
    perform bk_recompute_featured(l.id);
    r := bk_engage('featured', l.id, l.ref, l.ref, v_client, v_phone, v_from, v_until, null, uid);
    v_code_top := r.code;
  end if;

  return (json_build_object('ok', true, 'code_top', v_code_top, 'code_home', v_code_home)::jsonb || bk_admin_promo_info(p_token, l.id)::jsonb)::json;
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
             s.id as slot_id, s.enabled as home_enabled, s.starts_at as home_from, s.expires_at as home_until, s.sponsor_name, s.source as home_source,
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

-- the squares the promote dialog created earlier today are admin placements
update public.ad_slots set source = 'admin' where source is null and linked_listing_id is not null and starts_at is not null;

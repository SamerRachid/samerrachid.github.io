-- Balkoun · 2026-09-27 · free homepage feature as a reward for posting. Every N listings that actually go LIVE
-- (default 10) earn the poster one credit = one listing featured on the homepage for H hours (default 24); the very
-- first live listing earns a welcome credit (switchable). Agencies and individuals alike (individuals switchable).
-- The poster spends a credit from "my listings"; the panel sees balances, can grant/revoke, and changes the numbers.
-- Settings live in site_content(id=1).extras under reward_*: reward_on, reward_every, reward_hours, reward_welcome_on,
-- reward_users_on. Anti-abuse: a point is counted once per listing for life; a listing deleted within 7 days of its
-- point loses it; one reward-feature active per account at a time.

create table if not exists public.reward_events (
  id bigserial primary key,
  user_id uuid not null references public.users(id) on delete cascade,
  kind text not null check (kind in ('point','point_revoked','earned','welcome','used','granted','revoked')),
  listing_id bigint references public.listings(id) on delete set null,
  delta integer not null default 0,           -- credit change (earned/welcome/granted +, used/revoked −); 0 for points
  note text,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index if not exists reward_events_point_once on public.reward_events(listing_id) where kind = 'point';
create index if not exists reward_events_user on public.reward_events(user_id, kind);
alter table public.reward_events enable row level security;   -- reached only through security-definer functions

alter table public.listings add column if not exists featured_source text;   -- 'admin' | 'reward'

create or replace function public.bk_reward_cfg() returns jsonb
language sql stable security definer set search_path to 'public', 'extensions' as $function$
  select jsonb_build_object('reward_on', true, 'reward_every', 10, 'reward_hours', 24, 'reward_welcome_on', true, 'reward_users_on', true)
      || coalesce((select jsonb_object_agg(key, value) from jsonb_each(coalesce(extras, '{}'::jsonb)) where key like 'reward\_%'), '{}'::jsonb)
    from site_content where id = 1;
$function$;

create or replace function public.bk_reward_balance(p_uid uuid) returns json
language plpgsql stable security definer set search_path to 'public', 'extensions' as $function$
declare cfg jsonb := bk_reward_cfg(); pts int; cr int; ev int; act record;
begin
  select coalesce(sum(case kind when 'point' then 1 when 'point_revoked' then -1 else 0 end), 0),
         coalesce(sum(case when kind in ('earned','welcome','used','granted','revoked') then delta else 0 end), 0)
    into pts, cr from reward_events where user_id = p_uid;
  ev := greatest(1, coalesce((cfg->>'reward_every')::int, 10));
  select id, featured_until into act from listings where user_id = p_uid and featured_source = 'reward' and featured_until > now() order by featured_until desc limit 1;
  return json_build_object('on', coalesce(cfg->>'reward_on', 'true') <> 'false', 'every', ev, 'hours', greatest(1, coalesce((cfg->>'reward_hours')::int, 24)),
    'welcome_on', coalesce(cfg->>'reward_welcome_on', 'true') <> 'false', 'points', greatest(pts, 0), 'credits', greatest(cr, 0),
    'next_in', case when pts <= 0 then ev else ev - (pts % ev) end,
    'active_listing_id', act.id, 'active_until', act.featured_until);
end $function$;

-- tells the poster (site notification + one message on the channel they have) that a credit arrived
create or replace function public.bk_reward_notify(p_uid uuid, p_kind text, p_points int, p_every int) returns void
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare c contacts; u users; ch text; body_ar text; body_en text; camp uuid; nm text;
begin
  select * into u from users where id = p_uid; if u.id is null then return; end if;
  nm := coalesce(nullif(trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')), ''), u.phone, '');
  if p_kind = 'welcome' then
    body_ar := 'مبروك ' || nm || ' 🎉 إعلانك الأول نُشر على بلكون، وكسبت تمييزاً مجانياً: إعلان واحد على الصفحة الرئيسية لمدة 24 ساعة.' || E'\n' || 'استخدمه من صفحة «إعلاناتي»: https://balkoun.com/mine';
    body_en := 'Congratulations ' || nm || ' 🎉 Your first listing is live on Balkoun and you earned a free feature: one listing on the homepage for 24 hours.' || E'\n' || 'Use it from "My listings": https://balkoun.com/mine';
  else
    body_ar := 'مبروك ' || nm || ' 🎉 إعلانك رقم ' || p_points || ' نُشر على بلكون، وكسبت تمييزاً مجانياً: إعلان واحد على الصفحة الرئيسية لمدة 24 ساعة.' || E'\n' || 'استخدمه متى شئت من صفحة «إعلاناتي»: https://balkoun.com/mine' || E'\n' || 'كل ' || p_every || ' إعلانات منشورة = تمييز مجاني جديد.';
    body_en := 'Congratulations ' || nm || ' 🎉 Your listing #' || p_points || ' is live on Balkoun and you earned a free feature: one listing on the homepage for 24 hours.' || E'\n' || 'Use it whenever you like from "My listings": https://balkoun.com/mine' || E'\n' || 'Every ' || p_every || ' live listings = a new free feature.';
  end if;
  insert into notifications (user_id, type, title, body, link) values (p_uid, 'system', case when u.lang = 'en' then 'You earned a free feature 🎉' else 'كسبت تمييزاً مجانياً 🎉' end, case when u.lang = 'en' then body_en else body_ar end, '/mine');
  select * into c from contacts where user_id = p_uid order by created_at limit 1;
  if c.id is null then return; end if;
  ch := case when coalesce(c.phone,'') <> '' and c.wa_consent <> 'unsubscribed' then 'whatsapp'
             when c.tg_chat_id is not null and c.tg_consent <> 'unsubscribed' then 'telegram'
             when coalesce(c.email,'') <> '' and c.email_consent <> 'unsubscribed' then 'email' end;
  if ch is null then return; end if;
  insert into campaigns (title, kind, channels, subject, body_ar, body_en, country_code, consent_required, status, sent_at)
    values ('reward: ' || nm, 'manual', array[ch], case when u.lang = 'en' then 'You earned a free feature on Balkoun' else 'كسبت تمييزاً مجانياً على بلكون' end, body_ar, body_en, coalesce(c.country_code, u.country, 'SY'), false, 'sending', now())
    returning id into camp;
  insert into campaign_sends (campaign_id, trigger_type, contact_id, channel, status) values (camp, 'manual', c.id, ch, 'queued');
exception when others then null;
end $function$;

-- one point per listing the first time it goes live; a credit at every N-th point (+ the welcome credit at the first)
create or replace function public.bk_trg_reward_point() returns trigger
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare cfg jsonb; pts int; ev int;
begin
  if new.status <> 'live' or new.user_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'live' then return new; end if;
  cfg := bk_reward_cfg();
  if coalesce(cfg->>'reward_on', 'true') = 'false' then return new; end if;
  if coalesce(cfg->>'reward_users_on', 'true') = 'false' and not exists (select 1 from agencies where user_id = new.user_id and status = 'approved') then return new; end if;
  if exists (select 1 from users where id = new.user_id and role = 'admin') then return new; end if;
  if exists (select 1 from reward_events where listing_id = new.id and kind = 'point') then return new; end if;
  insert into reward_events (user_id, kind, listing_id) values (new.user_id, 'point', new.id);
  select coalesce(sum(case kind when 'point' then 1 when 'point_revoked' then -1 else 0 end), 0) into pts from reward_events where user_id = new.user_id;
  ev := greatest(1, coalesce((cfg->>'reward_every')::int, 10));
  if pts = 1 and coalesce(cfg->>'reward_welcome_on', 'true') <> 'false' then
    insert into reward_events (user_id, kind, listing_id, delta, note) values (new.user_id, 'welcome', new.id, 1, 'first live listing');
    perform bk_reward_notify(new.user_id, 'welcome', pts, ev);
  elsif pts > 0 and pts % ev = 0 then
    insert into reward_events (user_id, kind, listing_id, delta, note) values (new.user_id, 'earned', new.id, 1, pts || ' live listings');
    perform bk_reward_notify(new.user_id, 'earned', pts, ev);
  end if;
  return new;
exception when others then return new;
end $function$;
drop trigger if exists trg_reward_point on public.listings;
create trigger trg_reward_point after insert or update of status on public.listings for each row execute function public.bk_trg_reward_point();

-- a listing deleted within 7 days of earning its point gives the point back (no farming by post-and-delete)
create or replace function public.bk_trg_reward_revoke() returns trigger
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare p reward_events;
begin
  select * into p from reward_events where listing_id = old.id and kind = 'point';
  if p.id is not null and p.created_at > now() - interval '7 days' then
    insert into reward_events (user_id, kind, delta, note) values (p.user_id, 'point_revoked', 0, 'listing ' || coalesce(old.ref, old.id::text) || ' deleted within 7 days');
  end if;
  return old;
exception when others then return old;
end $function$;
drop trigger if exists trg_reward_revoke on public.listings;
create trigger trg_reward_revoke before delete on public.listings for each row execute function public.bk_trg_reward_revoke();

-- the member: balance + spend
create or replace function public.bk_my_rewards(p_token text) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid;
begin
  uid := bk_member_uid(p_token); if uid is null then return json_build_object('error', 'unauthorised'); end if;
  return bk_reward_balance(uid);
end $function$;
grant execute on function public.bk_my_rewards(text) to anon;

create or replace function public.bk_use_feature_credit(p_token text, p_listing bigint) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; b json; l listings; hrs int; untl timestamptz;
begin
  uid := bk_member_uid(p_token); if uid is null then return json_build_object('error', 'unauthorised'); end if;
  b := bk_reward_balance(uid);
  if not (b->>'on')::boolean then return json_build_object('error', 'off'); end if;
  if (b->>'credits')::int < 1 then return json_build_object('error', 'nocredit'); end if;
  if b->>'active_listing_id' is not null then return json_build_object('error', 'active', 'until', b->>'active_until'); end if;
  select * into l from listings where id = p_listing and user_id = uid;
  if l.id is null then return json_build_object('error', 'notyours'); end if;
  if l.status <> 'live' then return json_build_object('error', 'notlive'); end if;
  if l.featured_until is not null and l.featured_until > now() then return json_build_object('error', 'already', 'until', l.featured_until); end if;
  hrs := (b->>'hours')::int; untl := now() + make_interval(hours => hrs);
  update listings set featured_from = now(), featured_until = untl, is_featured = true, featured_source = 'reward' where id = l.id;
  insert into reward_events (user_id, kind, listing_id, delta, note) values (uid, 'used', l.id, -1, hrs || 'h feature');
  return json_build_object('ok', true, 'until', untl);
end $function$;
grant execute on function public.bk_use_feature_credit(text, bigint) to anon;

-- the panel: balances, settings, grant / revoke
create or replace function public.bk_admin_rewards(p_token text, p_country text default null) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return json_build_object(
    'cfg', bk_reward_cfg(),
    'balances', coalesce((select json_agg(x order by x.credits desc, x.points desc) from (
        select u.id as user_id, trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')) as name, u.member_no, u.phone, u.country,
               (select name from agencies a where a.user_id = u.id and a.status = 'approved' limit 1) as agency,
               coalesce(sum(case e.kind when 'point' then 1 when 'point_revoked' then -1 else 0 end), 0)::int as points,
               coalesce(sum(case when e.kind in ('earned','welcome','used','granted','revoked') then e.delta else 0 end), 0)::int as credits,
               (select featured_until from listings l where l.user_id = u.id and l.featured_source = 'reward' and l.featured_until > now() order by featured_until desc limit 1) as active_until
          from users u join reward_events e on e.user_id = u.id
         where bk_scope_ok(u.country, sc, al) group by u.id) x), '[]'::json),
    'events', coalesce((select json_agg(x) from (
        select e.id, e.kind, e.delta, e.note, e.created_at, e.listing_id, trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')) as name, u.member_no
          from reward_events e join users u on u.id = e.user_id where bk_scope_ok(u.country, sc, al) order by e.created_at desc limit 60) x), '[]'::json));
end $function$;
grant execute on function public.bk_admin_rewards(text, text) to anon;

create or replace function public.bk_admin_reward_adjust(p_token text, p_user uuid, p_delta integer, p_note text default null) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform bk_admin_guard(uid, (select country from users where id = p_user));
  if p_delta is null or p_delta = 0 or abs(p_delta) > 50 then return json_build_object('error', 'baddelta'); end if;
  insert into reward_events (user_id, kind, delta, note, created_by) values (p_user, case when p_delta > 0 then 'granted' else 'revoked' end, p_delta, nullif(trim(coalesce(p_note,'')), ''), uid);
  return bk_reward_balance(p_user);
end $function$;
grant execute on function public.bk_admin_reward_adjust(text, uuid, integer, text) to anon;

-- the admin's own featuring is marked, so the panel can tell the two apart
create or replace function public.bk_admin_feature_listing(p_token text, p_listing bigint, p_from timestamp with time zone, p_days integer) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; r public.engagements; v_ref text; v_client text; v_phone text;
begin
  uid := bk_admin_uid(p_token); perform bk_admin_guard(uid, (select country_code from listings where id = p_listing));
  if p_days is null or p_days < 1 then raise exception 'invalid duration'; end if;
  update listings set featured_from = p_from, featured_until = p_from + (p_days || ' days')::interval, featured_source = 'admin' where id = p_listing;
  perform bk_recompute_featured(p_listing);
  select l.ref, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')), coalesce(l.contact_phone,u.phone) into v_ref, v_client, v_phone from listings l left join users u on u.id=l.user_id where l.id=p_listing;
  r := public.bk_engage('featured', p_listing, v_ref, v_ref, v_client, v_phone, p_from, p_from + (p_days||' days')::interval, null, uid);
  return json_build_object('ok', true, 'code', r.code);
end $function$;

create or replace function public.bk_admin_list_featured(p_token text, p_country text default null) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  update listings set is_featured = (featured_from is not null and featured_until is not null and now() between featured_from and featured_until)
   where featured_until is not null and featured_until > now() - interval '1 day';
  return coalesce((select json_agg(x order by x.featured_from) from (
    select l.id, l.ref, l.price_usd, l.featured_from, l.featured_until, l.is_featured, l.country_code, l.featured_source,
           trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as poster_name
      from listings l left join users u on u.id = l.user_id
     where l.featured_until is not null and l.featured_until > now() - interval '1 day' and bk_scope_ok(l.country_code,sc,al)) x), '[]'::json);
end $function$;

-- the public poll (every visitor, every 90 s) now also expires / starts featured windows on its own, so a 24-hour
-- reward feature ends on time even when nobody opens the panel
create or replace function public.bk_public_featured_ids(p_country text default null) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
begin
  update listings set is_featured = (featured_from is not null and featured_until is not null and now() between featured_from and featured_until)
   where featured_until is not null and featured_until > now() - interval '1 day'
     and is_featured is distinct from (featured_from is not null and featured_until is not null and now() between featured_from and featured_until);
  return (select coalesce(json_agg(id), '[]'::json) from listings where is_featured = true and status = 'live' and (p_country is null or country_code = p_country));
end $function$;

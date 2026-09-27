-- Balkoun · 2026-09-27 · correction: the automatic reward window is PER ACCOUNT — 60 days (extras.reward_days) from the
-- day the account was created — not one global end date. Inside their window a poster earns the welcome credit and a
-- credit every N live listings; afterwards only the admin's manual grants add credits. Earned credits never expire.

update public.site_content set extras = (coalesce(extras, '{}'::jsonb) - 'reward_until') || jsonb_build_object('reward_days', 60)
 where id = 1 and not coalesce(extras, '{}'::jsonb) ? 'reward_days';

drop function if exists public.bk_reward_earning(jsonb);
create or replace function public.bk_reward_window_end(p_cfg jsonb, p_uid uuid) returns timestamptz
language sql stable security definer set search_path to 'public', 'extensions' as $function$
  select case when coalesce(nullif(p_cfg->>'reward_days', '')::int, 60) <= 0 then null   -- 0 = no end
              else (select created_at from users where id = p_uid) + make_interval(days => coalesce(nullif(p_cfg->>'reward_days', '')::int, 60)) end;
$function$;
create or replace function public.bk_reward_earning(p_cfg jsonb, p_uid uuid) returns boolean
language sql stable security definer set search_path to 'public', 'extensions' as $function$
  select coalesce(p_cfg->>'reward_on', 'true') <> 'false'
     and (bk_reward_window_end(p_cfg, p_uid) is null or bk_reward_window_end(p_cfg, p_uid) > now());
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
  return json_build_object('on', coalesce(cfg->>'reward_on', 'true') <> 'false', 'earning', bk_reward_earning(cfg, p_uid), 'until', bk_reward_window_end(cfg, p_uid),
    'days', coalesce(nullif(cfg->>'reward_days', '')::int, 60),
    'every', ev, 'hours', greatest(1, coalesce((cfg->>'reward_hours')::int, 24)),
    'welcome_on', coalesce(cfg->>'reward_welcome_on', 'true') <> 'false', 'points', greatest(pts, 0), 'credits', greatest(cr, 0),
    'next_in', case when pts <= 0 then ev else ev - (pts % ev) end,
    'active_listing_id', act.id, 'active_until', act.featured_until);
end $function$;

create or replace function public.bk_trg_reward_point() returns trigger
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare cfg jsonb; pts int; ev int;
begin
  if new.status <> 'live' or new.user_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'live' then return new; end if;
  cfg := bk_reward_cfg();
  if not bk_reward_earning(cfg, new.user_id) then return new; end if;   -- this account's 60 days are over (or the reward is off): nothing new is earned
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

-- the panel's balance list shows each account's window end too
create or replace function public.bk_admin_rewards(p_token text, p_country text default null) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
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
               (select featured_until from listings l where l.user_id = u.id and l.featured_source = 'reward' and l.featured_until > now() order by featured_until desc limit 1) as active_until,
               bk_reward_window_end(cfg, u.id) as window_end
          from users u join reward_events e on e.user_id = u.id
         where bk_scope_ok(u.country, sc, al) group by u.id) x), '[]'::json),
    'events', coalesce((select json_agg(x) from (
        select e.id, e.kind, e.delta, e.note, e.created_at, e.listing_id, trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')) as name, u.member_no
          from reward_events e join users u on u.id = e.user_id where bk_scope_ok(u.country, sc, al) order by e.created_at desc limit 60) x), '[]'::json));
end $function$;

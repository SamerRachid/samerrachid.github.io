-- Balkoun · 2026-09-27 · the automatic reward (welcome credit + a credit every N live listings) runs for a limited
-- window: extras.reward_until (default: 60 days from today). After it, no new points/credits are earned unless the
-- admin extends the date from the panel — but credits already earned stay and can be spent any time.

update public.site_content set extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object('reward_until', to_char(now() + interval '60 days', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
 where id = 1 and not coalesce(extras, '{}'::jsonb) ? 'reward_until';

create or replace function public.bk_reward_earning(p_cfg jsonb) returns boolean
language sql immutable as $function$
  select coalesce(p_cfg->>'reward_on', 'true') <> 'false'
     and (nullif(p_cfg->>'reward_until', '') is null or (p_cfg->>'reward_until')::timestamptz > now());
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
  return json_build_object('on', coalesce(cfg->>'reward_on', 'true') <> 'false', 'earning', bk_reward_earning(cfg), 'until', nullif(cfg->>'reward_until', ''),
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
  if not bk_reward_earning(cfg) then return new; end if;   -- window over (or switched off): nothing new is earned, balances stay
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

-- spending never expires: a credit earned during the window (or granted by hand) is usable whenever the owner likes
create or replace function public.bk_use_feature_credit(p_token text, p_listing bigint) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; b json; l listings; hrs int; untl timestamptz;
begin
  uid := bk_member_uid(p_token); if uid is null then return json_build_object('error', 'unauthorised'); end if;
  b := bk_reward_balance(uid);
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

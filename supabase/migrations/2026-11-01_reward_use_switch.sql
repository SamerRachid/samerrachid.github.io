-- Panel switch «reward_use_on» (extras, default on): when off, members can't spend saved feature credit themselves.
-- The credit stays on their account; the admin can still spend it for them from «الترويج» (bk_admin_promote is unchanged).
create or replace function public.bk_reward_balance(p_uid uuid) returns json
language plpgsql security definer set search_path = public, extensions as $$
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
    'active_listing_id', act.id, 'active_until', act.featured_until,
    'use_on', coalesce(cfg->>'reward_use_on', 'true') <> 'false');
end $$;

create or replace function public.bk_use_feature_credit(p_token text, p_listing bigint) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; b json; l listings; hrs int; sid bigint;
begin
  uid := bk_member_uid(p_token); if uid is null then return json_build_object('error', 'unauthorised'); end if;
  b := bk_reward_balance(uid);
  if (b->>'use_on') = 'false' then return json_build_object('error', 'off'); end if;
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
end $$;

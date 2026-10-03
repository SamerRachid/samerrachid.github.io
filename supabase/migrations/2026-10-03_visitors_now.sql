-- 2026-10-03 · "visitors on the site right now" for the admin dashboard (owner's request).
-- Every open tab (members AND guests) pings bk_visitor_ping on load and once a minute while visible; a visitor counts
-- as "now" when the last ping is under 5 minutes old (same window as the members' online_presence).
-- Admin reads bk_admin_visitors_now(p_token, p_country): totals, members/guests, devices, pages, countries, named members.

create table if not exists public.visitor_presence (
  visitor_id   text primary key,
  user_id      uuid,
  device       text,
  site_country text,
  country      text,
  view         text,
  first_seen   timestamptz not null default now(),
  last_seen    timestamptz not null default now()
);
create index if not exists idx_visitor_presence_last_seen on public.visitor_presence(last_seen);
alter table public.visitor_presence enable row level security;   -- no policies: only the definer functions below touch it
revoke all on public.visitor_presence from anon, authenticated;

create or replace function public.bk_visitor_ping(p_visitor text, p_device text default null, p_site_country text default null,
                                                  p_user uuid default null, p_view text default null, p_country text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_visitor is null or length(p_visitor) < 6 or length(p_visitor) > 64 then return; end if;
  insert into visitor_presence (visitor_id, user_id, device, site_country, country, view, first_seen, last_seen)
  values (p_visitor, p_user, left(p_device, 12), upper(left(p_site_country, 2)), upper(left(p_country, 2)), left(p_view, 24), now(), now())
  on conflict (visitor_id) do update
     set last_seen = now(),
         user_id = coalesce(excluded.user_id, visitor_presence.user_id),
         device = coalesce(excluded.device, visitor_presence.device),
         site_country = coalesce(excluded.site_country, visitor_presence.site_country),
         country = coalesce(excluded.country, visitor_presence.country),
         view = coalesce(excluded.view, visitor_presence.view);
  if random() < 0.02 then delete from visitor_presence where last_seen < now() - interval '2 days'; end if;
end $$;
revoke all on function public.bk_visitor_ping(text, text, text, uuid, text, text) from public;
grant execute on function public.bk_visitor_ping(text, text, text, uuid, text, text) to anon, authenticated;

create or replace function public.bk_admin_visitors_now(p_token text, p_country text default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; sc text; al text[]; t5 timestamptz := now() - interval '5 minutes'; t30 timestamptz := now() - interval '30 minutes';
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return json_build_object(
    'total',    (select count(*) from visitor_presence v where v.last_seen > t5 and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al)),
    'members',  (select count(*) from visitor_presence v where v.last_seen > t5 and v.user_id is not null and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al)),
    'guests',   (select count(*) from visitor_presence v where v.last_seen > t5 and v.user_id is null and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al)),
    'mobile',   (select count(*) from visitor_presence v where v.last_seen > t5 and v.device = 'mobile' and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al)),
    'desktop',  (select count(*) from visitor_presence v where v.last_seen > t5 and coalesce(v.device,'') <> 'mobile' and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al)),
    'last_30m', (select count(*) from visitor_presence v where v.last_seen > t30 and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al)),
    'pages',    coalesce((select json_agg(x) from (select v.view, count(*) n from visitor_presence v where v.last_seen > t5 and v.view is not null and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al) group by v.view order by n desc limit 6) x), '[]'::json),
    'countries',coalesce((select json_agg(x) from (select coalesce(v.country,'?') country, count(*) n from visitor_presence v where v.last_seen > t5 and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al) group by 1 order by n desc limit 6) x), '[]'::json),
    'members_list', coalesce((select json_agg(x) from (
        select u.id, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as name, v.view, v.device, v.last_seen
          from visitor_presence v join users u on u.id = v.user_id
         where v.last_seen > t5 and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al) order by v.last_seen desc limit 20) x), '[]'::json),
    'at', now());
end $$;
revoke all on function public.bk_admin_visitors_now(text, text) from public;
grant execute on function public.bk_admin_visitors_now(text, text) to anon, authenticated;

-- check
select bk_visitor_ping('migration_check_visitor_x', 'desktop', 'SY', null, 'home', 'SY');
select (select count(*) from visitor_presence where visitor_id = 'migration_check_visitor_x') as pinged;
delete from visitor_presence where visitor_id = 'migration_check_visitor_x';

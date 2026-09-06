-- 2026-09-06 · applied via the Supabase MCP (migrations: listing_status_hidden_and_trash_report, admin_storage_report,
-- analytics_v2, admin_user_activity_and_listing_stats). Copy of record.

-- listings: a real "hidden" status (admin hid it; distinct from a new pending submission)
alter table public.listings drop constraint if exists listings_status_check;
alter table public.listings add constraint listings_status_check
  check (status = any (array['draft'::text,'pending'::text,'live'::text,'hidden'::text,'sold'::text,'rented'::text,'expired'::text,'removed'::text]));

-- page views: visitor id, device, referrer, listing id
alter table public.page_views add column if not exists visitor_id text;
alter table public.page_views add column if not exists device text;
alter table public.page_views add column if not exists referrer text;
alter table public.page_views add column if not exists listing_id bigint;
create index if not exists page_views_created_idx on public.page_views (created_at desc);
create index if not exists page_views_listing_idx on public.page_views (listing_id) where listing_id is not null;

create or replace function public.bk_log_view2(p_path text, p_view text, p_user uuid, p_country text, p_token text default null,
                                               p_visitor text default null, p_device text default null, p_referrer text default null)
 returns void language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare lid bigint;
begin
  perform bk_require_member(p_token, p_user);
  lid := nullif(substring(coalesce(p_path,'') from '/listing/(\d+)'), '')::bigint;
  insert into page_views (path, view, user_id, country, visitor_id, device, referrer, listing_id)
  values (left(p_path,300), left(p_view,40), p_user, left(p_country,8), left(p_visitor,40), left(p_device,10), left(p_referrer,200), lid);
end $function$;

-- ad squares: impressions and clicks
create table if not exists public.ad_events (
  id bigserial primary key,
  slot_id bigint,
  kind text not null check (kind in ('view','click')),
  page text, country text, visitor_id text, user_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists ad_events_created_idx on public.ad_events (created_at desc);
alter table public.ad_events enable row level security;

create or replace function public.bk_log_ads(p_events jsonb, p_country text default null, p_visitor text default null, p_user uuid default null, p_token text default null)
 returns void language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare e jsonb; n int := 0;
begin
  perform bk_require_member(p_token, p_user);
  for e in select * from jsonb_array_elements(coalesce(p_events,'[]'::jsonb)) loop
    n := n + 1; exit when n > 40;
    if (e->>'kind') in ('view','click') and (e->>'slot') ~ '^\d+$' then
      insert into ad_events (slot_id, kind, page, country, visitor_id, user_id)
      values ((e->>'slot')::bigint, e->>'kind', left(e->>'page',40), left(p_country,8), left(p_visitor,40), p_user);
    end if;
  end loop;
end $function$;

-- admin analytics (see bk_admin_analytics in the live database for the full body: kpi + previous period, series,
-- top_listings, ads, pages, countries, devices, referrers, contact_kinds, users_activity, listings_status, health)
-- admin per-user activity and per-listing engagement
-- (bk_admin_user_activity, bk_admin_listing_stats, bk_admin_storage_report with trash — bodies as applied 2026-09-06)

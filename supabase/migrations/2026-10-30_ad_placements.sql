-- ════════════════════════════════════════════════════════════════════════════════════════════════════
-- 2026-10-30 · «الأماكن الإعلانية» (ad placements) — phase 1: the data under the panel's calendar
--
-- Four things are sold: featuring at the top of a city's results, a home-page square, a home-page banner,
-- and (new) a banner between the cards of the search results. A booking is an `engagements` row (it already
-- carries the client, phone, dates and the per-booking view/click counts); this adds what selling needs:
--   · price and payment, a private report link for the advertiser, a waiting list
--   · which placement and which governorate a booking takes, so a day's free places can be counted
--   · caps per placement, editable from the panel (site_content.extras): featuring 10 per governorate,
--     squares = the existing ad_max_squares, home banner 3, results banner 3 per governorate
--   · admin functions that change a booking AND the thing it sells together (until now editing a booking's
--     end date moved only the booking, not the listing's featuring or the square's expiry)
-- ad_slots gains `placement` (square | banner | results); everything that reads squares now reads squares
-- only, so a banner or results row can never appear in the home squares row or the Studio's squares list.
-- Nothing here changes what visitors see yet: the site reads banner/results rows in phase 2.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════

-- ── columns ─────────────────────────────────────────────────────────────────────────────────────────
alter table public.engagements
  add column if not exists price_usd   numeric(10,2),
  add column if not exists paid        boolean not null default false,
  add column if not exists paid_at     timestamptz,
  add column if not exists report_token text,
  add column if not exists placement   text,
  add column if not exists gov_id      integer references public.governorates(id) on delete set null,
  add column if not exists deal        text,
  add column if not exists wait_days   integer;
create unique index if not exists engagements_report_token_key on public.engagements(report_token) where report_token is not null;
alter table public.engagements drop constraint if exists engagements_status_check;
alter table public.engagements add constraint engagements_status_check check (status = any (array['active','ended','cancelled','waiting']));
alter table public.engagements drop constraint if exists engagements_placement_check;
alter table public.engagements add constraint engagements_placement_check check (placement is null or placement = any (array['featured','square','banner','results']));
alter table public.engagements drop constraint if exists engagements_deal_check;
alter table public.engagements add constraint engagements_deal_check check (deal is null or deal = any (array['sale','rent']));

alter table public.ad_slots
  add column if not exists placement   text not null default 'square',
  add column if not exists banner_no   smallint,
  add column if not exists target_gov  integer references public.governorates(id) on delete set null,
  add column if not exists target_deal text;
alter table public.ad_slots drop constraint if exists ad_slots_placement_check;
alter table public.ad_slots add constraint ad_slots_placement_check check (placement = any (array['square','banner','results']));
alter table public.ad_slots drop constraint if exists ad_slots_banner_no_check;
alter table public.ad_slots add constraint ad_slots_banner_no_check check (banner_no is null or banner_no between 1 and 3);
alter table public.ad_slots drop constraint if exists ad_slots_target_deal_check;
alter table public.ad_slots add constraint ad_slots_target_deal_check check (target_deal is null or target_deal = any (array['sale','rent']));

-- existing bookings learn their placement and governorate
update public.engagements e set placement = 'featured', gov_id = l.governorate_id
  from public.listings l where e.kind = 'featured' and e.placement is null and l.id = e.ref_id;
update public.engagements set placement = 'featured' where kind = 'featured' and placement is null;
update public.engagements set placement = 'square' where kind = 'ad' and placement is null;
update public.engagements set placement = 'banner' where kind = 'banner' and placement is null;
-- a new booking is stamped by its kind (bk_engage and the old Studio paths keep working untouched)
create or replace function public.bk_trg_engagement_placement() returns trigger language plpgsql set search_path to 'public' as $$
begin
  if new.placement is null then
    new.placement := case new.kind when 'featured' then 'featured' when 'banner' then 'banner'
                       else coalesce((select a.placement from ad_slots a where a.id = new.ref_id), 'square') end;
  end if;
  if new.placement = 'featured' and new.gov_id is null and new.ref_id is not null then
    select governorate_id into new.gov_id from listings where id = new.ref_id;
  end if;
  if new.placement = 'results' and new.gov_id is null and new.ref_id is not null then
    select target_gov, coalesce(new.deal, target_deal) into new.gov_id, new.deal from ad_slots where id = new.ref_id;
  end if;
  return new;
end $$;
drop trigger if exists trg_engagement_placement on public.engagements;
create trigger trg_engagement_placement before insert on public.engagements for each row execute function public.bk_trg_engagement_placement();

-- ── squares stay squares ────────────────────────────────────────────────────────────────────────────
create or replace function public.bk_ad_squares_used(p_cc text, p_except bigint default null) returns integer language sql stable set search_path to 'public' as $$
  select count(*)::int from public.ad_slots
   where country_code = coalesce(p_cc,'SY') and enabled = true and placement = 'square'
     and (expires_at is null or expires_at >= now())
     and (p_except is null or id <> p_except)
$$;
do $do$
declare d text; o text;
begin
  d := pg_get_functiondef('public.bk_public_ad_slots(text)'::regprocedure);
  o := $q$where a.enabled = true and a.country_code = coalesce(p_country,'SY')$q$;
  if position(o in d) = 0 then raise exception 'bk_public_ad_slots: where line not found'; end if;
  execute replace(d, o, o || $q$ and a.placement = 'square'$q$);
  d := pg_get_functiondef('public.bk_admin_list_ads(text,text)'::regprocedure);
  o := $q$from ad_slots where bk_scope_ok(country_code, sc, al)$q$;
  if position(o in d) = 0 then raise exception 'bk_admin_list_ads: from line not found'; end if;
  execute replace(d, o, $q$from ad_slots where bk_scope_ok(country_code, sc, al) and placement = 'square'$q$);
end $do$;

-- ── caps and counting ───────────────────────────────────────────────────────────────────────────────
-- extras keys: ads_cap_featured (per governorate) · ad_max_squares (existing) · ads_cap_banner · ads_cap_results (per governorate)
create or replace function public.bk_placement_cap(p_placement text) returns integer language sql stable set search_path to 'public' as $$
  select greatest(1, coalesce(case p_placement
      when 'featured' then nullif(extras->>'ads_cap_featured','')::int
      when 'square'   then nullif(extras->>'ad_max_squares','')::int
      when 'banner'   then nullif(extras->>'ads_cap_banner','')::int
      when 'results'  then nullif(extras->>'ads_cap_results','')::int end,
    case p_placement when 'featured' then 10 when 'square' then 15 else 3 end))
  from public.site_content where id = 1
$$;
-- the last moment a booking runs: its end date, or the moment it was stopped early (no end = open-ended)
create or replace function public.bk_eng_until(e public.engagements) returns timestamptz language sql immutable as $$
  select case when e.status = 'waiting' then null
              when e.status in ('ended','cancelled') and e.ended_at is not null then least(coalesce(e.ends_at, e.ended_at), e.ended_at)
              else coalesce(e.ends_at, 'infinity'::timestamptz) end
$$;
-- places taken on one day: featuring and results banners count per governorate (a results banner for «all cities» takes
-- a place in every governorate); squares and the home banner count once for the whole site
create or replace function public.bk_placement_used(p_cc text, p_placement text, p_gov integer, p_day date, p_except bigint)
returns integer language sql stable set search_path to 'public' as $$
  select count(*)::int from public.engagements e
   where coalesce(e.country_code,'SY') = coalesce(p_cc,'SY') and e.placement = p_placement and e.status <> 'waiting'
     and (p_except is null or e.id <> p_except)
     and e.starts_at::date <= p_day and public.bk_eng_until(e)::date >= p_day
     and (p_placement not in ('featured','results') or p_gov is null or e.gov_id = p_gov or (p_placement = 'results' and e.gov_id is null))
$$;
-- the first day in [from, to] that has no free place (null = the whole stay fits)
create or replace function public.bk_placement_first_full(p_cc text, p_placement text, p_gov integer, p_from date, p_to date, p_except bigint)
returns date language sql stable set search_path to 'public' as $$
  select d::date from generate_series(p_from, coalesce(p_to, p_from + 30), interval '1 day') d
   where public.bk_placement_used(p_cc, p_placement, p_gov, d::date, p_except) >= public.bk_placement_cap(p_placement)
   order by d limit 1
$$;
revoke all on function public.bk_placement_used(text,text,integer,date,bigint) from public, anon, authenticated;
revoke all on function public.bk_placement_first_full(text,text,integer,date,date,bigint) from public, anon, authenticated;
revoke all on function public.bk_trg_engagement_placement() from public, anon, authenticated;

-- ── the calendar's data ─────────────────────────────────────────────────────────────────────────────
create or replace function public.bk_admin_placements(p_token text, p_country text, p_from date, p_to date)
returns json language plpgsql security definer set search_path to 'public' as $$
declare uid uuid; sc text; al text[]; v_cc text := upper(coalesce(nullif(p_country,''),'SY'));
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['engage','featured','ads']::text[], 'bk_admin_placements', null, false, left(coalesce(p_from::text,''),300), nullif(upper(p_country),''));
  if v_cc = 'ALL' then v_cc := 'SY'; end if;
  sc := bk_admin_scope(uid, v_cc); al := bk_admin_allowed(uid);
  return json_build_object(
    'caps', json_build_object('featured', bk_placement_cap('featured'), 'square', bk_placement_cap('square'), 'banner', bk_placement_cap('banner'), 'results', bk_placement_cap('results')),
    'govs', coalesce((select json_agg(json_build_object('id', g.id, 'name', g.name_ar) order by g.sort_order, g.id) from governorates g
                       where g.country_code = v_cc and g.merged_into is null and g.enabled is not false), '[]'::json),
    'bookings', coalesce((select json_agg(row_to_json(x) order by x.starts_at) from (
      select e.id, e.code, e.kind, e.placement, e.gov_id, e.deal, e.client_name, e.phone, e.title, e.ref_id, e.ref_text, e.notes, e.status,
             e.starts_at, e.ends_at, e.ended_at, bk_eng_until(e) as until, e.price_usd, e.paid, e.paid_at, e.report_token, e.wait_days, e.created_at,
             (select g.name_ar from governorates g where g.id = e.gov_id) as gov_name,
             case when e.kind = 'featured' then (select json_build_object('ref', l.ref, 'status', l.status, 'cover', (select ph.url from listing_photos ph where ph.listing_id = l.id and coalesce(ph.kind,'photo') = 'photo' order by ph.sort_order limit 1),
                    'views', (select count(*) from page_views v where v.listing_id = l.id and v.created_at >= e.starts_at and v.created_at <= least(bk_eng_until(e), now())),
                    'contacts', (select count(*) from contact_events c where c.listing_id = l.id and c.created_at >= e.starts_at and c.created_at <= least(bk_eng_until(e), now())))
                  from listings l where l.id = e.ref_id)
                  when e.kind = 'ad' then (select json_build_object('label', a.label, 'sponsor', a.sponsor_name, 'image', coalesce(a.image_url, a.image_urls->>0), 'enabled', a.enabled,
                    'banner_no', a.banner_no, 'link', a.link_url, 'listing_id', a.linked_listing_id,
                    'views', (select count(*) from ad_events v where v.slot_id = a.id and v.kind = 'view' and v.created_at >= e.starts_at and v.created_at <= least(bk_eng_until(e), now())),
                    'clicks', (select count(*) from ad_events v where v.slot_id = a.id and v.kind = 'click' and v.created_at >= e.starts_at and v.created_at <= least(bk_eng_until(e), now())))
                  from ad_slots a where a.id = e.ref_id)
                  else null end as obj
        from engagements e
       where bk_scope_ok(coalesce(e.country_code,'SY'), sc, al) and coalesce(e.country_code,'SY') = v_cc
         and (e.status = 'waiting' or (e.starts_at::date <= p_to and bk_eng_until(e)::date >= p_from))
    ) x), '[]'::json));
end $$;

-- price, payment, client details of a booking
create or replace function public.bk_admin_booking_save(p_token text, p_id bigint, p_client text, p_phone text, p_notes text, p_price numeric, p_paid boolean)
returns json language plpgsql security definer set search_path to 'public' as $$
declare uid uuid; e engagements;
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['engage']::text[], 'bk_admin_booking_save', (select coalesce(country_code,'SY') from engagements where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from engagements where id=p_id));
  select * into e from engagements where id = p_id; if e.id is null then return json_build_object('error','nobooking'); end if;
  perform bk_admin_guard(uid, coalesce(e.country_code,'SY'));
  update engagements set client_name = coalesce(p_client, client_name), phone = coalesce(p_phone, phone), notes = coalesce(p_notes, notes),
         price_usd = coalesce(p_price, price_usd),
         paid = coalesce(p_paid, paid), paid_at = case when p_paid is true and not paid then now() when p_paid is false then null else paid_at end
   where id = p_id;
  return json_build_object('ok', true);
end $$;

-- move or extend a booking: the featuring / the square or banner moves with it, and the new stay must fit the caps
create or replace function public.bk_admin_booking_dates(p_token text, p_id bigint, p_starts timestamptz, p_ends timestamptz)
returns json language plpgsql security definer set search_path to 'public' as $$
declare uid uuid; e engagements; v_full date; v_cc text;
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['engage','featured','ads']::text[], 'bk_admin_booking_dates', (select coalesce(country_code,'SY') from engagements where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from engagements where id=p_id));
  select * into e from engagements where id = p_id; if e.id is null then return json_build_object('error','nobooking'); end if;
  v_cc := coalesce(e.country_code,'SY'); perform bk_admin_guard(uid, v_cc);
  if p_ends is not null and p_ends <= coalesce(p_starts, e.starts_at) then return json_build_object('error','baddates'); end if;
  v_full := bk_placement_first_full(v_cc, e.placement, e.gov_id, coalesce(p_starts, e.starts_at)::date, coalesce(p_ends, coalesce(p_starts, e.starts_at) + interval '30 days')::date, e.id);
  if v_full is not null then return json_build_object('error','full','day',v_full); end if;
  update engagements set starts_at = coalesce(p_starts, starts_at), ends_at = p_ends,
         status = case when status in ('ended','cancelled') and coalesce(p_ends,'infinity') > now() then 'active' else status end,
         ended_at = case when status in ('ended','cancelled') and coalesce(p_ends,'infinity') > now() then null else ended_at end
   where id = p_id returning * into e;
  if e.kind = 'featured' and e.ref_id is not null then
    update listings set featured_from = e.starts_at, featured_until = e.ends_at, featured_source = coalesce(featured_source,'admin') where id = e.ref_id;
    perform bk_recompute_featured(e.ref_id);
  elsif e.kind = 'ad' and e.ref_id is not null then
    update ad_slots set starts_at = e.starts_at, expires_at = e.ends_at, enabled = true where id = e.ref_id;
  end if;
  return json_build_object('ok', true);
end $$;

-- stop a booking now: the featuring ends / the square or banner switches off
create or replace function public.bk_admin_booking_stop(p_token text, p_id bigint)
returns json language plpgsql security definer set search_path to 'public' as $$
declare uid uuid; e engagements;
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['engage','featured','ads']::text[], 'bk_admin_booking_stop', (select coalesce(country_code,'SY') from engagements where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from engagements where id=p_id));
  select * into e from engagements where id = p_id; if e.id is null then return json_build_object('error','nobooking'); end if;
  perform bk_admin_guard(uid, coalesce(e.country_code,'SY'));
  update engagements set status = case when status = 'waiting' then 'cancelled' else 'ended' end, ended_at = now() where id = p_id;
  if e.status <> 'waiting' and e.kind = 'featured' and e.ref_id is not null then
    update listings set featured_until = least(coalesce(featured_until, now()), now()) where id = e.ref_id;
    perform bk_recompute_featured(e.ref_id);
  elsif e.status <> 'waiting' and e.kind = 'ad' and e.ref_id is not null then
    update ad_slots set enabled = false, expires_at = least(coalesce(expires_at, now()), now()) where id = e.ref_id;
  end if;
  return json_build_object('ok', true);
end $$;

-- a client waiting for a place: kept on the calendar's waiting list until you book them in
create or replace function public.bk_admin_wait_add(p_token text, p_country text, p_placement text, p_gov integer, p_days integer, p_client text, p_phone text, p_notes text, p_listing bigint)
returns json language plpgsql security definer set search_path to 'public' as $$
declare uid uuid; r engagements; v_cc text := upper(coalesce(nullif(p_country,''),'SY'));
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['engage']::text[], 'bk_admin_wait_add', v_cc, true, left(coalesce(p_placement,''),300), v_cc);
  perform bk_admin_guard(uid, v_cc);
  if p_placement not in ('featured','square','banner','results') then return json_build_object('error','badplacement'); end if;
  insert into engagements (code, kind, ref_id, ref_text, title, client_name, phone, starts_at, status, notes, created_by, country_code, placement, gov_id, wait_days)
    values (bk_engagement_code('wait'), case when p_placement = 'featured' then 'featured' else 'ad' end, p_listing,
            (select ref from listings where id = p_listing), coalesce(nullif(trim(coalesce(p_client,'')),''), 'انتظار'),
            nullif(trim(coalesce(p_client,'')),''), nullif(trim(coalesce(p_phone,'')),''), now(), 'waiting', p_notes, uid, v_cc, p_placement, p_gov, p_days)
    returning * into r;
  return row_to_json(r);
end $$;

-- the private report link of a booking (made once, then always the same)
create or replace function public.bk_admin_booking_report(p_token text, p_id bigint)
returns json language plpgsql security definer set search_path to 'public' as $$
declare uid uuid; e engagements; v_t text;
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['engage','featured','ads']::text[], 'bk_admin_booking_report', (select coalesce(country_code,'SY') from engagements where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from engagements where id=p_id));
  select * into e from engagements where id = p_id; if e.id is null then return json_build_object('error','nobooking'); end if;
  perform bk_admin_guard(uid, coalesce(e.country_code,'SY'));
  v_t := e.report_token;
  if v_t is null then
    v_t := substr(md5(random()::text || clock_timestamp()::text || p_id::text), 1, 12) || substr(md5(random()::text || p_id::text), 1, 12);
    update engagements set report_token = v_t where id = p_id;
  end if;
  return json_build_object('ok', true, 'token', v_t);
end $$;

-- what the advertiser sees from their link: the booking, and its numbers day by day (no phone, no notes, no price)
create or replace function public.bk_public_booking_report(p_t text)
returns json language plpgsql security definer set search_path to 'public' as $$
declare e engagements; v_to timestamptz;
begin
  if p_t is null or length(p_t) < 20 then return json_build_object('error','notfound'); end if;
  select * into e from engagements where report_token = p_t; if e.id is null then return json_build_object('error','notfound'); end if;
  v_to := least(bk_eng_until(e), now());
  return json_build_object('title', e.title, 'client', e.client_name, 'placement', e.placement, 'starts_at', e.starts_at, 'until', bk_eng_until(e),
    'gov', (select name_ar from governorates where id = e.gov_id), 'ref', e.ref_text,
    'days', coalesce((select json_agg(json_build_object('day', d::date,
        'views', case when e.kind = 'featured' then (select count(*) from page_views v where v.listing_id = e.ref_id and v.created_at::date = d::date)
                      else (select count(*) from ad_events v where v.slot_id = e.ref_id and v.kind = 'view' and v.created_at::date = d::date) end,
        'clicks', case when e.kind = 'featured' then (select count(*) from contact_events c where c.listing_id = e.ref_id and c.created_at::date = d::date)
                      else (select count(*) from ad_events v where v.slot_id = e.ref_id and v.kind = 'click' and v.created_at::date = d::date) end) order by d)
      from generate_series(e.starts_at::date, greatest(e.starts_at, v_to)::date, interval '1 day') d), '[]'::json));
end $$;
grant execute on function public.bk_public_booking_report(text) to anon, authenticated;

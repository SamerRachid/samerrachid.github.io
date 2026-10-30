-- 2026-10-30 · «الأماكن الإعلانية» phase 3 (owner's idea): the banner between search results becomes a card the size of a
-- listing card, and a new «بانر جانبي» sits under the map beside the results on a computer. The side banner is booked like
-- the results banner: per governorate (or all of them) and sale / rent, with its own number of places (extras ads_cap_side).

alter table public.engagements drop constraint if exists engagements_placement_check;
alter table public.engagements add constraint engagements_placement_check check (placement is null or placement = any (array['featured','square','banner','results','side']));
alter table public.ad_slots drop constraint if exists ad_slots_placement_check;
alter table public.ad_slots add constraint ad_slots_placement_check check (placement = any (array['square','banner','results','side']));

create or replace function public.bk_trg_engagement_placement() returns trigger language plpgsql set search_path to 'public' as $$
begin
  if new.placement is null then
    new.placement := case new.kind when 'featured' then 'featured' when 'banner' then 'banner'
                       else coalesce((select a.placement from ad_slots a where a.id = new.ref_id), 'square') end;
  end if;
  if new.placement = 'featured' and new.gov_id is null and new.ref_id is not null then
    select governorate_id into new.gov_id from listings where id = new.ref_id;
  end if;
  if new.placement in ('results','side') and new.gov_id is null and new.ref_id is not null then
    select target_gov, coalesce(new.deal, target_deal) into new.gov_id, new.deal from ad_slots where id = new.ref_id;
  end if;
  return new;
end $$;

create or replace function public.bk_placement_cap(p_placement text) returns integer language sql stable set search_path to 'public' as $$
  select greatest(1, coalesce(case p_placement
      when 'featured' then nullif(extras->>'ads_cap_featured','')::int
      when 'square'   then nullif(extras->>'ad_max_squares','')::int
      when 'banner'   then nullif(extras->>'ads_cap_banner','')::int
      when 'results'  then nullif(extras->>'ads_cap_results','')::int
      when 'side'     then nullif(extras->>'ads_cap_side','')::int end,
    case p_placement when 'featured' then 10 when 'square' then 15 else 3 end))
  from public.site_content where id = 1
$$;

create or replace function public.bk_placement_used(p_cc text, p_placement text, p_gov integer, p_day date, p_except bigint)
returns integer language sql stable set search_path to 'public' as $$
  select count(*)::int from public.engagements e
   where coalesce(e.country_code,'SY') = coalesce(p_cc,'SY') and e.placement = p_placement and e.status <> 'waiting'
     and (p_except is null or e.id <> p_except)
     and e.starts_at::date <= p_day and public.bk_eng_until(e)::date >= p_day
     and (p_placement not in ('featured','results','side') or p_gov is null or e.gov_id = p_gov or (p_placement in ('results','side') and e.gov_id is null))
$$;

create or replace function public.bk_placement_first_full(p_cc text, p_placement text, p_gov integer, p_from date, p_to date, p_except bigint)
returns date language sql stable set search_path to 'public' as $$
  select d::date from generate_series(p_from, coalesce(p_to, p_from + 30), interval '1 day') d
   where case when p_placement in ('results','side') and p_gov is null then
                exists (select 1 from public.governorates g where g.country_code = coalesce(p_cc,'SY') and g.merged_into is null and g.enabled is not false
                           and public.bk_placement_used(p_cc, p_placement, g.id, d::date, p_except) >= public.bk_placement_cap(p_placement))
              else public.bk_placement_used(p_cc, p_placement, p_gov, d::date, p_except) >= public.bk_placement_cap(p_placement) end
   order by d limit 1
$$;
revoke all on function public.bk_placement_used(text,text,integer,date,bigint) from public, anon, authenticated;
revoke all on function public.bk_placement_first_full(text,text,integer,date,date,bigint) from public, anon, authenticated;
revoke all on function public.bk_trg_engagement_placement() from public, anon, authenticated;

create or replace function public.bk_public_placements(p_country text)
returns json language sql stable security definer set search_path to 'public' as $$
  select json_build_object(
    'banner', coalesce((select json_agg(json_build_object('id', a.id, 'banner_no', a.banner_no, 'url', coalesce(nullif(a.image_url,''), a.image_urls->>0),
                          'type', a.media_type, 'link', a.link_url, 'sponsor', a.sponsor_name) order by a.position, a.id)
                        from ad_slots a
                       where a.placement = 'banner' and a.enabled and a.country_code = coalesce(p_country,'SY')
                         and (a.starts_at is null or a.starts_at <= now()) and (a.expires_at is null or a.expires_at >= now())
                         and coalesce(nullif(a.image_url,''), a.image_urls->>0, '') <> ''), '[]'::json),
    'results', coalesce((select json_agg(json_build_object('id', a.id, 'url', coalesce(nullif(a.image_url,''), a.image_urls->>0), 'type', a.media_type,
                          'link', a.link_url, 'sponsor', a.sponsor_name, 'label', a.label, 'top', a.overlay_top, 'bottom', a.overlay_bottom,
                          'gov', a.target_gov, 'deal', a.target_deal) order by a.position, a.id)
                        from ad_slots a
                       where a.placement = 'results' and a.enabled and a.country_code = coalesce(p_country,'SY')
                         and (a.starts_at is null or a.starts_at <= now()) and (a.expires_at is null or a.expires_at >= now())
                         and coalesce(nullif(a.image_url,''), a.image_urls->>0, '') <> ''), '[]'::json),
    'side', coalesce((select json_agg(json_build_object('id', a.id, 'url', coalesce(nullif(a.image_url,''), a.image_urls->>0), 'type', a.media_type,
                          'link', a.link_url, 'sponsor', a.sponsor_name, 'gov', a.target_gov, 'deal', a.target_deal) order by a.position, a.id)
                        from ad_slots a
                       where a.placement = 'side' and a.enabled and a.country_code = coalesce(p_country,'SY')
                         and (a.starts_at is null or a.starts_at <= now()) and (a.expires_at is null or a.expires_at >= now())
                         and coalesce(nullif(a.image_url,''), a.image_urls->>0, '') <> ''), '[]'::json))
$$;
grant execute on function public.bk_public_placements(text) to anon, authenticated;

-- the rest takes «side» wherever it takes «results» (edited in place, so nothing else in these functions changes)
do $do$
declare d text; o text;
begin
  d := pg_get_functiondef('public.bk_admin_placement_ad_save(text,text,bigint,text,integer,integer,text,text,text,text,text,text,timestamptz,timestamptz,text,text,numeric,boolean)'::regprocedure);
  o := $q$p_placement not in ('banner','results')$q$;
  if position(o in d) = 0 then raise exception 'bk_admin_placement_ad_save: placement check not found'; end if;
  d := replace(d, o, $q$p_placement not in ('banner','results','side')$q$);
  d := replace(d, $q$p_placement = 'results'$q$, $q$p_placement in ('results','side')$q$);
  execute d;

  d := pg_get_functiondef('public.bk_admin_wait_add(text,text,text,integer,integer,text,text,text,bigint)'::regprocedure);
  o := $q$p_placement not in ('featured','square','banner','results')$q$;
  if position(o in d) = 0 then raise exception 'bk_admin_wait_add: placement check not found'; end if;
  execute replace(d, o, $q$p_placement not in ('featured','square','banner','results','side')$q$);

  d := pg_get_functiondef('public.bk_admin_placements(text,text,date,date)'::regprocedure);
  o := $q$'results', bk_placement_cap('results'))$q$;
  if position(o in d) = 0 then raise exception 'bk_admin_placements: caps line not found'; end if;
  execute replace(d, o, $q$'results', bk_placement_cap('results'), 'side', bk_placement_cap('side'))$q$);
end $do$;

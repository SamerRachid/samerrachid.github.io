-- 2026-10-30 · owner: the ad between search results can also be «صورة كاملة»: the photo, video or GIF fills the whole card
-- (ad_slots.layout 'full'), besides the card with a 4:3 photo, name, text and button (null / 'card').

alter table public.ad_slots add column if not exists layout text;
alter table public.ad_slots drop constraint if exists ad_slots_layout_check;
alter table public.ad_slots add constraint ad_slots_layout_check check (layout is null or layout = any (array['card','full']));

-- the site reads the layout with the results ads
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
                          'gov', a.target_gov, 'deal', a.target_deal, 'layout', a.layout) order by a.position, a.id)
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

do $do$
declare d text; o text;
begin
  -- the panel's calendar shows it with the booking
  d := pg_get_functiondef('public.bk_admin_placements(text,text,date,date)'::regprocedure);
  o := $q$'banner_no', a.banner_no, 'link', a.link_url$q$;
  if position(o in d) = 0 then raise exception 'bk_admin_placements: ad object not found'; end if;
  execute replace(d, o, $q$'banner_no', a.banner_no, 'layout', a.layout, 'link', a.link_url$q$);
end $do$;

-- saving a results ad: the layout comes along (a separate small call, so the booking function keeps its signature)
create or replace function public.bk_admin_ad_layout(p_token text, p_id bigint, p_layout text)
returns json language plpgsql security definer set search_path to 'public' as $$
declare uid uuid; v_cc text;
begin
  select coalesce(country_code,'SY') into v_cc from ad_slots where id = p_id;
  if v_cc is null then return json_build_object('error','noad'); end if;
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['ads']::text[], 'bk_admin_ad_layout', v_cc, true, left(coalesce(p_id::text,''),300), v_cc);
  perform bk_admin_guard(uid, v_cc);
  if p_layout is not null and p_layout not in ('card','full') then return json_build_object('error','badlayout'); end if;
  update ad_slots set layout = p_layout where id = p_id;
  return json_build_object('ok', true);
end $$;
grant execute on function public.bk_admin_ad_layout(text,bigint,text) to anon, authenticated;

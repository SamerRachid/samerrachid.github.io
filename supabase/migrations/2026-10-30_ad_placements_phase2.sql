-- 2026-10-30 · «الأماكن الإعلانية» phase 2: the site shows booked home banners and the banner between search results,
-- and the panel books them. Both are ad_slots rows (placement 'banner' with banner_no 1–3, or 'results' with an optional
-- governorate and deal); their booking is the usual engagements row, so the calendar, caps, report and view/click counts
-- (ad_events, logged by the site for any slot id) work for them as for squares.

-- what the site shows now: running banner rows and results rows with something to show
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
                         and coalesce(nullif(a.image_url,''), a.image_urls->>0, '') <> ''), '[]'::json))
$$;
grant execute on function public.bk_public_placements(text) to anon, authenticated;

-- book (or change) a home banner or a results banner: the ad row and its booking together, inside the caps
create or replace function public.bk_admin_placement_ad_save(p_token text, p_country text, p_id bigint, p_placement text, p_banner_no integer,
    p_gov integer, p_deal text, p_label text, p_sponsor text, p_url text, p_media_type text, p_link text,
    p_starts timestamptz, p_ends timestamptz, p_client text, p_phone text, p_price numeric, p_paid boolean)
returns json language plpgsql security definer set search_path to 'public' as $$
declare uid uuid; v_cc text := upper(coalesce(nullif(p_country,''),'SY')); v_id bigint := p_id; v_pos int; v_eng engagements; v_full date; v_ex bigint;
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['ads']::text[], 'bk_admin_placement_ad_save', v_cc, true, left(coalesce(p_placement,'')||' '||coalesce(p_id::text,''),300), v_cc);
  perform bk_admin_guard(uid, v_cc);
  if p_placement not in ('banner','results') then return json_build_object('error','badplacement'); end if;
  if p_placement = 'banner' and (p_banner_no is null or p_banner_no not between 1 and 3) then return json_build_object('error','badbanner'); end if;
  if p_deal is not null and p_deal not in ('sale','rent') then return json_build_object('error','baddeal'); end if;
  if coalesce(p_url,'') = '' then return json_build_object('error','nomedia'); end if;
  if p_starts is null or p_ends is null or p_ends <= p_starts then return json_build_object('error','baddates'); end if;
  if v_id is not null then select id into v_ex from engagements where kind = 'ad' and ref_id = v_id order by created_at desc limit 1; end if;
  v_full := bk_placement_first_full(v_cc, p_placement, case when p_placement = 'results' then p_gov end, p_starts::date, p_ends::date, v_ex);
  if v_full is not null then return json_build_object('error','full','day',v_full); end if;
  if v_id is null then
    select coalesce(max(position),0)+1 into v_pos from ad_slots where country_code = v_cc;
    insert into ad_slots (position, placement, banner_no, target_gov, target_deal, image_url, image_urls, media_type, link_url, label, sponsor_name,
                          starts_at, expires_at, enabled, country_code, source)
      values (v_pos, p_placement, case when p_placement = 'banner' then p_banner_no end, case when p_placement = 'results' then p_gov end,
              case when p_placement = 'results' then p_deal end, p_url, '[]'::jsonb, case when p_media_type = 'video' then 'video' else 'image' end,
              nullif(trim(coalesce(p_link,'')),''), nullif(trim(coalesce(p_label,'')),''), nullif(trim(coalesce(p_sponsor,'')),''), p_starts, p_ends, true, v_cc, 'admin')
      returning id into v_id;
  else
    update ad_slots set placement = p_placement, banner_no = case when p_placement = 'banner' then p_banner_no end,
           target_gov = case when p_placement = 'results' then p_gov end, target_deal = case when p_placement = 'results' then p_deal end,
           image_url = p_url, media_type = case when p_media_type = 'video' then 'video' else 'image' end, link_url = nullif(trim(coalesce(p_link,'')),''),
           label = nullif(trim(coalesce(p_label,'')),''), sponsor_name = nullif(trim(coalesce(p_sponsor,'')),''), starts_at = p_starts, expires_at = p_ends, enabled = true
     where id = v_id and country_code = v_cc;
  end if;
  select * into v_eng from engagements where kind = 'ad' and ref_id = v_id and status = 'active' order by created_at desc limit 1;
  if v_eng.id is null then
    v_eng := bk_engage('ad', v_id, null, coalesce(nullif(trim(coalesce(p_sponsor,'')),''), nullif(trim(coalesce(p_label,'')),''), 'إعلان #'||v_id),
                       nullif(trim(coalesce(p_client,'')),''), nullif(trim(coalesce(p_phone,'')),''), p_starts, p_ends, null, uid);
  end if;
  update engagements set placement = p_placement, gov_id = case when p_placement = 'results' then p_gov end, deal = case when p_placement = 'results' then p_deal end,
         client_name = coalesce(nullif(trim(coalesce(p_client,'')),''), client_name), phone = coalesce(nullif(trim(coalesce(p_phone,'')),''), phone),
         starts_at = p_starts, ends_at = p_ends, price_usd = coalesce(p_price, price_usd),
         paid = coalesce(p_paid, paid), paid_at = case when p_paid is true and not paid then now() when p_paid is false then null else paid_at end,
         country_code = v_cc
   where id = v_eng.id;
  return json_build_object('ok', true, 'id', v_id, 'code', v_eng.code);
end $$;

-- a results banner for «all governorates» needs a free place in EVERY governorate (each one counted on its own,
-- not the sum of all of them); everything else is unchanged
create or replace function public.bk_placement_first_full(p_cc text, p_placement text, p_gov integer, p_from date, p_to date, p_except bigint)
returns date language sql stable set search_path to 'public' as $$
  select d::date from generate_series(p_from, coalesce(p_to, p_from + 30), interval '1 day') d
   where case when p_placement = 'results' and p_gov is null then
                exists (select 1 from public.governorates g where g.country_code = coalesce(p_cc,'SY') and g.merged_into is null and g.enabled is not false
                           and public.bk_placement_used(p_cc, 'results', g.id, d::date, p_except) >= public.bk_placement_cap('results'))
              else public.bk_placement_used(p_cc, p_placement, p_gov, d::date, p_except) >= public.bk_placement_cap(p_placement) end
   order by d limit 1
$$;
revoke all on function public.bk_placement_first_full(text,text,integer,date,date,bigint) from public, anon, authenticated;

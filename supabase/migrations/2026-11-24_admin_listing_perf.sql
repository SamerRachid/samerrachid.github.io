-- 2026-11-24 panel «أداء الإعلانات»: per listing, for a chosen period, the page views and every kind of contact click
-- (show number, call, WhatsApp, visit request) and saves; ranked by any of them, searched, a page at a time.
-- p_days 0 = since the start. Read only.
create or replace function public.bk_admin_listing_perf(p_token text, p_country text default null, p_days integer default 30, p_q text default null,
                                                        p_sort text default 'views', p_offset integer default 0, p_limit integer default 50)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; sc text; al text[]; t0 timestamptz; w text[]; srt text := coalesce(nullif(p_sort,''),'views'); res json;
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, array['stats','listings_view']::text[], 'bk_admin_listing_perf', null, false, left(coalesce(p_q,''),300), nullif(upper(p_country),''));
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  t0 := case when coalesce(p_days,0) <= 0 then '-infinity'::timestamptz else now() - (least(p_days, 3650) || ' days')::interval end;
  w := bk_kw_words(coalesce(p_q,'')); if cardinality(w) = 0 then w := null; end if;
  with v as (select listing_id, count(*) n from page_views where listing_id is not null and created_at >= t0 group by 1),
       c as (select listing_id, count(*) filter (where kind='reveal_phone') reveal, count(*) filter (where kind='call') calls,
                    count(*) filter (where kind='whatsapp') wa, count(*) filter (where kind='visit_request') visit, count(*) n
               from contact_events where created_at >= t0 group by 1),
       s as (select listing_id, count(*) n from saved_listings where created_at >= t0 group by 1),
       base as (
         select l.id, l.ref, l.status, l.deal, l.property_type, l.price_usd, l.created_at, l.country_code, g.name_ar as gov, a.name_ar as area,
                trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as poster_name, u.phone as poster_phone,
                (select ag.name from agencies ag where ag.user_id = l.user_id and ag.status = 'approved' limit 1) as agency_name,
                coalesce(v.n,0) as views, coalesce(c.reveal,0) as reveal, coalesce(c.calls,0) as calls, coalesce(c.wa,0) as whatsapp,
                coalesce(c.visit,0) as visit, coalesce(c.n,0) as contacts, coalesce(s.n,0) as saves, l.views as views_total
           from listings l join governorates g on g.id=l.governorate_id left join areas a on a.id=l.area_id left join users u on u.id=l.user_id
           left join v on v.listing_id = l.id left join c on c.listing_id = l.id left join s on s.listing_id = l.id
          where bk_scope_ok(l.country_code,sc,al)),
       filt as (select * from base b where w is null or bk_kw_hit(bk_kw_norm(concat_ws(' ', b.ref, b.id::text, b.gov, b.area, b.poster_name, b.agency_name, b.poster_phone)), w)),
       page as (select * from filt f
                 order by case srt when 'reveal' then f.reveal when 'calls' then f.calls when 'whatsapp' then f.whatsapp when 'visit' then f.visit
                                   when 'saves' then f.saves when 'contacts' then f.contacts else f.views end desc, f.views desc, f.created_at desc, f.id desc
                 offset greatest(0, coalesce(p_offset,0)) limit greatest(1, least(coalesce(p_limit,50), 500)))
  select json_build_object(
    'total', (select count(*) from filt),
    'totals', (select json_build_object('views', coalesce(sum(views),0), 'reveal', coalesce(sum(reveal),0), 'calls', coalesce(sum(calls),0), 'whatsapp', coalesce(sum(whatsapp),0),
                                        'visit', coalesce(sum(visit),0), 'contacts', coalesce(sum(contacts),0), 'saves', coalesce(sum(saves),0)) from filt),
    'rows', coalesce((select json_agg(json_build_object('id',p.id,'ref',p.ref,'status',p.status,'deal',p.deal,'property_type',p.property_type,'price_usd',p.price_usd,
              'created_at',p.created_at,'country_code',p.country_code,'gov',p.gov,'area',p.area,'poster_name',p.poster_name,'agency_name',p.agency_name,
              'views',p.views,'reveal',p.reveal,'calls',p.calls,'whatsapp',p.whatsapp,'visit',p.visit,'contacts',p.contacts,'saves',p.saves,'views_total',p.views_total,
              'cover',(select coalesce(nullif(ph.thumb_url,''), ph.url) from listing_photos ph where ph.listing_id=p.id and coalesce(ph.kind,'photo')='photo' order by ph.sort_order, ph.id limit 1))
            order by case srt when 'reveal' then p.reveal when 'calls' then p.calls when 'whatsapp' then p.whatsapp when 'visit' then p.visit
                              when 'saves' then p.saves when 'contacts' then p.contacts else p.views end desc, p.views desc, p.created_at desc, p.id desc) from page p), '[]'::json)
  ) into res;
  return res;
end $function$;
revoke all on function public.bk_admin_listing_perf(text,text,integer,text,text,integer,integer) from public;
grant execute on function public.bk_admin_listing_perf(text,text,integer,text,text,integer,integer) to anon, authenticated, service_role;

-- the listing drawer's numbers: the contact count split by kind (same function, four more fields)
create or replace function public.bk_admin_listing_stats(p_token text, p_days integer default 30, p_country text default null)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; t0 timestamptz; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['stats','listings_view']::text[], 'bk_admin_listing_stats', null, false, left(coalesce(p_days::text,''),300), nullif(upper(p_country),''));
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  t0 := now() - (greatest(1, least(coalesce(p_days,30), 3650)) || ' days')::interval;
  return coalesce((select json_agg(x) from (
    select l.id,
           (select count(*) from page_views v where v.listing_id=l.id and v.created_at >= t0) as views,
           coalesce(c.n,0) as contacts, coalesce(c.reveal,0) as reveal, coalesce(c.calls,0) as calls, coalesce(c.wa,0) as whatsapp, coalesce(c.visit,0) as visit,
           (select count(*) from saved_listings s where s.listing_id=l.id) as saves,
           l.views as views_total
      from listings l
      left join (select listing_id, count(*) n, count(*) filter (where kind='reveal_phone') reveal, count(*) filter (where kind='call') calls,
                        count(*) filter (where kind='whatsapp') wa, count(*) filter (where kind='visit_request') visit
                   from contact_events where created_at >= t0 group by 1) c on c.listing_id = l.id
     where bk_scope_ok(l.country_code,sc,al)) x), '[]'::json);
end $function$;
